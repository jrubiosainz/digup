"""The returns assistant on Microsoft Foundry Agent Service: its versions, its policy documents and its chat turns.

    python -m src.agent publish          a new version, from prompts/returns-assistant.md and src/tools.py
    python -m src.agent promote 7        the chat serves version 7 from now on
    python -m src.agent policies *.pdf   a new vector store with the policy PDFs
    python -m src.agent chat             talk to the promoted version in the terminal
"""

from __future__ import annotations

import argparse
import datetime as dt
import io
import json
import os
import re
import subprocess
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AgentEndpointConfig,
    FixedRatioVersionSelectionRule,
    PromptAgentDefinition,
    ProtocolConfiguration,
    ResponsesProtocolConfiguration,
    VersionSelector,
)
from azure.identity import DefaultAzureCredential
from openai import OpenAI
from openai.types.responses import Response
from openai.types.responses.response_input_param import FunctionCallOutput
from pypdf import PdfReader, PdfWriter

from src.tools import agent_tools, call_tool

ENDPOINT = os.environ["FOUNDRY_PROJECT_ENDPOINT"]
MODEL = os.environ.get("FOUNDRY_MODEL_NAME", "gpt-5-mini")
AGENT = "returns-assistant"
PROMPT = Path(__file__).parent.parent / "prompts" / "returns-assistant.md"
MAX_TOOL_ROUNDS = 5
PAGE = re.compile(r"^(?P<name>.+)\.p(?P<page>\d+)\.pdf$")

credential = DefaultAzureCredential()
project = AIProjectClient(endpoint=ENDPOINT, credential=credential)


def publish() -> str:
    """A new version of the agent. Customers don't see it until it's promoted."""
    git = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=False)
    agent = project.agents.create_version(
        agent_name=AGENT,
        description="Contoso Outdoor's returns assistant",
        definition=PromptAgentDefinition(
            model=MODEL,
            instructions=PROMPT.read_text(encoding="utf-8"),
            tools=agent_tools(),
        ),
        metadata={"commit": git.stdout.strip() or "unknown"},
    )
    print(f"Published {agent.name} version {agent.version}. Next: python -m src.evaluate --version {agent.version}")
    return agent.version


def promote(version: str) -> None:
    """Points the agent's endpoint, the one the chat talks to, at `version`. Promote the last one to roll back."""
    project.agents.update_details(
        agent_name=AGENT,
        agent_endpoint=AgentEndpointConfig(
            version_selector=VersionSelector(version_selection_rules=[
                FixedRatioVersionSelectionRule(agent_version=version, traffic_percentage=100),
            ]),
            protocol_configuration=ProtocolConfiguration(responses=ResponsesProtocolConfiguration()),
        ),
    )
    print(f"{AGENT} now serves version {version}.")


def chat_client(version: str | None = None) -> OpenAI:
    """A client for the agent's endpoint, which serves the promoted version. With a `version`, a client for the
    whole project instead: only there can a request pick a version (see turn)."""
    return project.get_openai_client() if version else project.get_openai_client(agent_name=AGENT)


@dataclass
class Event:
    """What the chat streams: a "tool" event as each tool starts, then one "answer"."""

    kind: str
    data: dict[str, Any]


def turn(openai: OpenAI, conversation_id: str, text: str, version: str | None = None) -> Iterator[Event]:
    """One customer message, answered. Runs the functions the agent asks for until it replies.

    With a `version` it's that version that answers, not the promoted one; `openai` is then chat_client(version)."""
    extra = {"agent_reference": {"type": "agent_reference", "name": AGENT, "version": version}} if version else None
    response = openai.responses.create(conversation=conversation_id, input=text, extra_body=extra)
    rounds = 0
    while calls := [item for item in response.output if item.type == "function_call"]:
        rounds += 1
        if rounds > MAX_TOOL_ROUNDS:
            raise RuntimeError(f"{AGENT} still wanted tools after {MAX_TOOL_ROUNDS} rounds")
        outputs: list[FunctionCallOutput] = []
        for call in calls:
            yield Event("tool", {"name": call.name, "arguments": json.loads(call.arguments)})
            outputs.append(FunctionCallOutput(type="function_call_output", call_id=call.call_id,
                                              output=call_tool(call.name, call.arguments)))
        response = openai.responses.create(conversation=conversation_id, input=outputs, extra_body=extra)
    yield Event("answer", {"text": response.output_text, "sources": sources(response), "response_id": response.id})


def sources(response: Response) -> list[str]:
    """The policy pages an answer cites, the way the chat shows them: "Return policy.pdf · p. 2"."""
    found: list[str] = []
    for item in response.output:
        if item.type != "message":
            continue
        for part in item.content:
            for annotation in getattr(part, "annotations", []):
                if annotation.type != "file_citation":
                    continue
                page = PAGE.match(annotation.filename)
                label = f"{page['name']}.pdf · p. {int(page['page'])}" if page else annotation.filename
                if label not in found:
                    found.append(label)
    return found


def upload_policies(paths: list[Path]) -> str:
    """A new vector store with the policy PDFs, one file per page: File Search cites files, and a page is what a
    person checks an answer against (checklist §3). Old policies stay behind, in the old store, so they can't be
    cited again: in week 2 of the pilot the agent quoted the 2025 return policy because they hadn't."""
    pages = []
    for path in paths:
        for number, page in enumerate(PdfReader(path).pages, start=1):
            writer = PdfWriter()
            writer.add_page(page)
            buffer = io.BytesIO()
            writer.write(buffer)
            pages.append((f"{path.stem}.p{number}.pdf", buffer.getvalue(), "application/pdf"))
    openai = project.get_openai_client()
    store = openai.vector_stores.create(name=f"policies-{dt.datetime.now(dt.UTC):%Y-%m-%d}")
    batch = openai.vector_stores.file_batches.upload_and_poll(vector_store_id=store.id, files=pages)
    if batch.file_counts.failed:
        raise SystemExit(f"{batch.file_counts.failed} of {len(pages)} pages failed, so {store.id} is incomplete.")
    print(f"{len(pages)} pages in {store.id}. Next: azd env set POLICY_VECTOR_STORE_ID {store.id}, then publish.")
    return store.id


def chat() -> None:
    """The promoted version in the terminal, tools and all. An empty line ends it."""
    openai = chat_client()
    conversation = openai.conversations.create()
    while text := input("\nyou › ").strip():
        for event in turn(openai, conversation.id, text):
            if event.kind == "tool":
                print(f"  ƒ {event.data['name']}({json.dumps(event.data['arguments'])})")
                continue
            print(f"\n{event.data['text']}")
            for source in event.data["sources"]:
                print(f"  ↳ {source}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m src.agent", description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("publish", help="a new version, from the prompt and the tools")
    commands.add_parser("promote", help="serve one version in the chat").add_argument("version")
    commands.add_parser("policies", help="a new policy vector store").add_argument("pdfs", nargs="+", type=Path)
    commands.add_parser("chat", help="talk to the promoted version")
    arguments = parser.parse_args()
    match arguments.command:
        case "publish":
            publish()
        case "promote":
            promote(arguments.version)
        case "policies":
            upload_policies(arguments.pdfs)
        case "chat":
            chat()


if __name__ == "__main__":
    main()
