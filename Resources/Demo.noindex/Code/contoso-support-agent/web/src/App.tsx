import { Fragment, useEffect, useRef, useState, type FormEvent } from "react";
import { describe, handOver, send, startConversation, type ToolCall } from "./chat";

type Turn =
  | { kind: "customer"; text: string }
  | { kind: "tool"; call: ToolCall; running: boolean }
  | { kind: "agent"; text: string; sources: string[] }
  | { kind: "notice"; text: string };

const GREETING =
  "Hi! I'm the Contoso Outdoor assistant. I can check your orders, start a return or help you choose gear.";
const STARTERS = ["Track my order", "Start a return", "Which tent fits four?"];

export function App() {
  const [conversation, setConversation] = useState<string>();
  const [turns, setTurns] = useState<Turn[]>([]);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [ticket, setTicket] = useState<string>();
  const bottom = useRef<HTMLDivElement>(null);

  const add = (turn: Turn) => setTurns((all) => [...all, turn]);
  const toolsDone = () =>
    setTurns((all) => all.map((turn) => (turn.kind === "tool" ? { ...turn, running: false } : turn)));

  useEffect(() => {
    let current = true;
    startConversation()
      .then((id) => current && setConversation(id))
      .catch(() => current && add({ kind: "notice", text: "The assistant isn't available right now. Please try again soon." }));
    return () => {
      current = false;
    };
  }, []);

  useEffect(() => bottom.current?.scrollIntoView({ behavior: "smooth", block: "end" }), [turns]);

  async function ask(text: string) {
    if (!conversation || busy || !text.trim()) return;
    setDraft("");
    setBusy(true);
    add({ kind: "customer", text: text.trim() });
    try {
      for await (const event of send(conversation, text.trim())) {
        toolsDone();
        if (event.kind === "tool") add({ kind: "tool", call: event.data, running: true });
        else if (event.kind === "answer") add({ kind: "agent", text: event.data.text, sources: event.data.sources });
        else add({ kind: "notice", text: event.data.message });
      }
    } catch {
      add({ kind: "notice", text: "That didn't go through. Please try again, or tap Talk to a person." });
    } finally {
      toolsDone();
      setBusy(false);
    }
  }

  async function talkToPerson() {
    if (!conversation) return;
    try {
      const reference = await handOver(conversation);
      setTicket(reference);
      add({ kind: "notice", text: `Our team has the whole conversation and will reply by email. Reference ${reference}.` });
    } catch {
      add({ kind: "notice", text: "We couldn't reach the team just now. Please try again in a minute." });
    }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void ask(draft);
  }

  const last = turns.at(-1);
  const typing = busy && !(last?.kind === "tool" && last.running);
  const offer = conversation && !ticket ? handoverAt(turns) : -1;

  return (
    <div className="app">
      <header className="top">
        <div className="mark" aria-hidden="true" />
        <div className="brand">
          Contoso Outdoor<small>Customer support</small>
        </div>
        <span className="pill">AI assistant</span>
        <span className="note">Answers are AI-generated. Check important details.</span>
      </header>

      <main className="thread" aria-live="polite">
        <Agent text={GREETING} sources={[]} />
        {turns.length === 0 && (
          <div className="chips">
            {STARTERS.map((starter) => (
              <button key={starter} type="button" className="chip" disabled={!conversation} onClick={() => void ask(starter)}>
                {starter}
              </button>
            ))}
          </div>
        )}
        {turns.map((turn, index) => (
          <Fragment key={index}>
            <Row turn={turn} />
            {index === offer && (
              <button type="button" className="chip person" onClick={() => void talkToPerson()}>
                Talk to a person
              </button>
            )}
          </Fragment>
        ))}
        {typing && (
          <div className="typing" role="status" aria-label="The assistant is writing">
            •••
          </div>
        )}
        <div ref={bottom} />
      </main>

      <form className={draft ? "composer typed" : "composer"} onSubmit={submit}>
        <input
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="Ask about an order, a return or our gear…"
          maxLength={2000}
          aria-label="Your message"
          autoFocus
        />
        <button type="submit" className="send" aria-label="Send" disabled={!draft.trim() || busy || !conversation}>
          ↑
        </button>
      </form>
    </div>
  );
}

/** Talk to a person goes under the agent's latest offer of one, or under the latest thing that went wrong. */
function handoverAt(turns: Turn[]): number {
  for (let index = turns.length - 1; index >= 0; index--) {
    const turn = turns[index];
    if (turn.kind === "notice" || (turn.kind === "agent" && /talk to a person/i.test(turn.text))) return index;
    if (turn.kind === "customer") break;
  }
  return -1;
}

function Row({ turn }: { turn: Turn }) {
  switch (turn.kind) {
    case "customer":
      return <div className="msg user">{turn.text}</div>;
    case "tool":
      return (
        <div className={turn.running ? "tool running" : "tool"}>
          {turn.call.name}
          <span>({describe(turn.call)})</span>
        </div>
      );
    case "agent":
      return <Agent text={turn.text} sources={turn.sources} />;
    case "notice":
      return <p className="notice">{turn.text}</p>;
  }
}

function Agent({ text, sources }: { text: string; sources: string[] }) {
  return (
    <div className="msg agent">
      <div className="who">Contoso assistant</div>
      <Rich text={text} />
      {sources.length > 0 && (
        <div className="cites">
          {sources.map((source) => (
            <span key={source} className="cite">
              {source}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

/** The agent writes plain paragraphs, with order and return numbers in **bold** (prompts/returns-assistant.md). */
function Rich({ text }: { text: string }) {
  return (
    <>
      {text.split(/\n{2,}/).map((paragraph, index) => (
        <p key={index}>
          {paragraph.split(/\*\*(.+?)\*\*/g).map((part, i) => (i % 2 ? <b key={i}>{part}</b> : part))}
        </p>
      ))}
    </>
  );
}
