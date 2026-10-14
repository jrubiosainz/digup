// The chat's side of src/app.py: a conversation, each answer streamed as server-sent events, and the handover.

export type ToolCall = { name: string; arguments: Record<string, unknown> };
export type Answer = { text: string; sources: string[]; response_id: string };
export type ChatEvent =
  | { kind: "tool"; data: ToolCall }
  | { kind: "answer"; data: Answer }
  | { kind: "error"; data: { message: string } };

async function post<T>(path: string, body?: unknown): Promise<T> {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${path}: ${response.status}`);
  return response.json() as Promise<T>;
}

export async function startConversation(): Promise<string> {
  return (await post<{ conversation_id: string }>("/api/conversations")).conversation_id;
}

/** One message to the agent. Yields each tool as it starts, then the answer, or an error. */
export async function* send(conversationId: string, text: string): AsyncGenerator<ChatEvent> {
  const response = await fetch("/api/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ conversation_id: conversationId, text }),
  });
  if (!response.ok || !response.body) throw new Error(`/api/messages: ${response.status}`);
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) return;
    buffer += value;
    let end: number;
    while ((end = buffer.indexOf("\n\n")) >= 0) {
      const block = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      const kind = /^event: (.+)$/m.exec(block)?.[1];
      const data = /^data: (.+)$/m.exec(block)?.[1];
      if (kind && data) yield { kind, data: JSON.parse(data) } as ChatEvent;
    }
  }
}

/** A ticket for the support team with the whole conversation. Returns its reference. */
export async function handOver(conversationId: string): Promise<string> {
  return (await post<{ ticket: string }>("/api/handover", { conversation_id: conversationId })).ticket;
}

/** order_id="48213", reason="damaged": a tool call's arguments, the way the chips show them. */
export function describe(call: ToolCall): string {
  return Object.entries(call.arguments)
    .map(([name, value]) => `${name}=${JSON.stringify(value)}`)
    .join(", ");
}
