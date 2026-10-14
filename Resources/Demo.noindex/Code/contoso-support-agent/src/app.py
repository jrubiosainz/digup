"""The chat's backend: a conversation per visitor, each answer streamed as server-sent events, and the handover to a
person with the whole conversation attached. In production it serves the chat itself too, from web/dist.

    uv run uvicorn src.app:app --reload --port 8000
"""

from __future__ import annotations

import json
import logging
import os
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import fastapi
import httpx
from azure.ai.projects.telemetry import AIProjectInstrumentor
from azure.monitor.opentelemetry import configure_azure_monitor
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from src import agent

if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    # Before the app and the OpenAI client exist, so that both are traced (checklist §7). Traces keep the steps, the
    # tool calls and the timings, but not what anybody wrote: content recording stays off (checklist §4).
    configure_azure_monitor()
    AIProjectInstrumentor().instrument(enable_content_recording=False)

log = logging.getLogger(__name__)
app = fastapi.FastAPI(title="Contoso Outdoor support", docs_url=None, redoc_url=None, openapi_url=None)
openai = agent.chat_client()
WEB = Path(__file__).parent.parent / "web" / "dist"
SORRY = "Something went wrong on our side. Please try again, or tap Talk to a person."


class Message(BaseModel):
    conversation_id: str
    text: str = Field(min_length=1, max_length=2000)


class Handover(BaseModel):
    conversation_id: str


def sse(kind: str, data: dict[str, Any]) -> str:
    return f"event: {kind}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


@app.post("/api/conversations")
def start() -> dict[str, str]:
    return {"conversation_id": openai.conversations.create().id}


@app.post("/api/messages")
def answer(message: Message) -> StreamingResponse:
    """The agent's answer as server-sent events: "tool" as each tool starts, then "answer", or "error"."""

    def events() -> Iterator[str]:
        try:
            for event in agent.turn(openai, message.conversation_id, message.text):
                yield sse(event.kind, event.data)
        except Exception as error:  # noqa: BLE001
            log.warning("turn failed: %s", type(error).__name__)
            yield sse("error", {"message": SORRY})

    return StreamingResponse(events(), media_type="text/event-stream", headers={"Cache-Control": "no-store"})


@app.post("/api/handover")
def handover(request: Handover) -> dict[str, str]:
    """A ticket on the support desk with the whole conversation, so the customer doesn't repeat a thing (§6)."""
    transcript = []
    for item in openai.conversations.items.list(request.conversation_id, order="asc"):
        if item.type == "message":
            text = " ".join(part.text for part in item.content if hasattr(part, "text"))
            transcript.append(f"{item.role}: {text}")
        elif item.type == "function_call":
            transcript.append(f"tool: {item.name}({item.arguments})")
    token = agent.credential.get_token("api://contoso-support-desk/.default").token
    response = httpx.post(
        f"{os.environ['SUPPORT_DESK_API']}/tickets",
        json={"queue": "returns", "source": "support-agent", "transcript": "\n".join(transcript)},
        headers={"Authorization": f"Bearer {token}"},
    )
    response.raise_for_status()
    return {"ticket": str(response.json()["id"])}


app.mount("/", StaticFiles(directory=WEB, html=True, check_dir=False), name="web")  # last, so /api/… comes first
