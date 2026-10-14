"""Scores a version of the agent on the golden set before it's promoted (checklist §3).

Every conversation runs here first, tools and all, because Foundry can't call our functions for us. create_return
runs dry, so no real returns are opened. Then Foundry's evaluators grade the stored responses.

    python -m src.evaluate --version 7

Exits with 1 when any metric misses its target, so that the version isn't promoted.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

from azure.ai.projects.models import (
    AzureAIDataSourceConfig,
    AzureAIResponsesEvalRunDataSource,
    ResponseRetrievalItemGenerationParams,
    TestingCriterionAzureAIEvaluator,
)
from openai.types.evals.create_eval_completions_run_data_source_param import (
    SourceFileContent,
    SourceFileContentContent,
)

from src import agent

TARGETS = {  # scores out of 5, but task adherence is the share of answers that pass
    "intent_resolution": 4.0,
    "tool_call_accuracy": 4.0,
    "task_adherence": 0.90,
    "groundedness": 4.0,
    "relevance": 4.0,
}
PASS_FAIL = {"task_adherence"}


def answer_all(golden: Path, version: str) -> list[str]:
    """Each golden conversation, answered by `version` in a conversation of its own. Returns the final responses."""
    openai = agent.chat_client(version)
    lines = [line for line in golden.read_text(encoding="utf-8").splitlines() if line.strip()]
    response_ids = []
    for number, line in enumerate(lines, start=1):
        item = json.loads(line)
        conversation = openai.conversations.create(metadata={"golden": item["id"]})
        for event in agent.turn(openai, conversation.id, item["query"], version=version):
            if event.kind == "answer":
                response_ids.append(event.data["response_id"])
        print(f"  {number}/{len(lines)} {item['id']}", end="\x1b[K\r", flush=True)
    return response_ids


def score(response_ids: list[str], version: str) -> dict[str, float]:
    """Foundry's built-in evaluators over the stored responses. Means for scores, pass rates for pass/fail."""
    openai = agent.project.get_openai_client()
    evaluation = openai.evals.create(
        name=f"{agent.AGENT} golden set",
        data_source_config=AzureAIDataSourceConfig(type="azure_ai_source", scenario="responses"),
        testing_criteria=[
            TestingCriterionAzureAIEvaluator(type="azure_ai_evaluator", name=name, evaluator_name=f"builtin.{name}",
                                             initialization_parameters={"deployment_name": agent.MODEL})
            for name in TARGETS
        ],
    )
    run = openai.evals.runs.create(
        eval_id=evaluation.id,
        name=f"{agent.AGENT} v{version}",
        data_source=AzureAIResponsesEvalRunDataSource(
            type="azure_ai_responses",
            item_generation_params=ResponseRetrievalItemGenerationParams(
                type="response_retrieval",
                data_mapping={"response_id": "{{item.resp_id}}"},
                source=SourceFileContent(type="file_content", content=[
                    SourceFileContentContent(item={"resp_id": response_id}) for response_id in response_ids
                ]),
            ),
        ),
    )
    while run.status not in ("completed", "failed", "canceled"):
        time.sleep(10)
        run = openai.evals.runs.retrieve(run_id=run.id, eval_id=evaluation.id)
    print(f"Report: {run.report_url}")
    if run.status != "completed":
        sys.exit(f"The evaluation run {run.status}.")
    results: dict[str, list[float]] = {name: [] for name in TARGETS}
    for output in openai.evals.runs.output_items.list(run_id=run.id, eval_id=evaluation.id):
        for result in output.results:
            if result.name in PASS_FAIL:
                results[result.name].append(1.0 if result.passed else 0.0)
            elif result.name in results and result.score is not None:
                results[result.name].append(result.score)
    return {name: sum(values) / len(values) for name, values in results.items() if values}


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m src.evaluate", description=__doc__.splitlines()[0])
    parser.add_argument("--version", required=True, help="the agent version to score, from python -m src.agent publish")
    parser.add_argument("--golden", type=Path, default=Path("evals/golden.jsonl"),
                        help="112 anonymized conversations in English and Spanish, kept in SharePoint (Customer Care "
                             "› Agent pilot), not here. evals/sample.jsonl shows the format.")
    arguments = parser.parse_args()
    os.environ["RETURNS_DRY_RUN"] = "1"

    print(f"{agent.AGENT} v{arguments.version} answers {arguments.golden}…")
    response_ids = answer_all(arguments.golden, arguments.version)
    print(f"\nGrading {len(response_ids)} answers…")
    results = score(response_ids, arguments.version)

    missed = []
    for name, target in TARGETS.items():
        value = results.get(name)
        if name in PASS_FAIL:
            shown, wanted = ("–" if value is None else f"{value:.0%}"), f"≥ {target:.0%}"
        else:
            shown, wanted = ("–" if value is None else f"{value:.1f}"), f"≥ {target:.1f}"
        met = value is not None and value >= target
        print(f"  {name:<20} {shown:>5}   {wanted:<6} {'ok' if met else 'MISSED'}")
        if not met:
            missed.append(name)
    # TODO: compare with the promoted version too, and fail when any metric drops by more than 5% (checklist §3).
    if missed:
        sys.exit(f"\nNot ready: {', '.join(missed)}. Don't promote v{arguments.version}.")
    print(f"\nEvery target met. Next: python -m src.agent promote {arguments.version}")


if __name__ == "__main__":
    main()
