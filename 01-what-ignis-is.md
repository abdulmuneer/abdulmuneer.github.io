---
title: "Part 1 — What It Is, and How to Run It"
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-ember.svg
sidebar:
  nav: "ignis"
---

*Part 1 of the Ignis expedition. [Part 0](./00-curiosity-and-the-plan.md) was the why. This is the what: the shape of the repo, the one design decision everything else hangs off, the control flow of a single turn, how to extend it, and how to build it and watch it run. If you only read one part to understand the artifact, read this one.*

<p style="text-align:center"><img class="brand-logo" src="/assets/images/ignis-process.svg" alt="Harness and model in one OS process" style="width:560px;max-width:100%"></p>



## What Ignis is, in one breath

Ignis is a Mojo-native agent harness that runs the model **in the same OS process** as the control plane. There is no `curl`, no separate `max serve`, no REST hop. Compiled Mojo embeds CPython through `std.python` and drives MAX's in-process pipeline from there. The default model is `Qwen/Qwen3-8B`, loaded and graph-compiled in-process. A deterministic fixture backend runs the *same* harness with no model at all, which is what keeps CI fast and the design honest.

It is not a line-by-line port of [`ds4`](https://github.com/antirez/ds4) — the translation is architectural. Concretely, Ignis:

- runs the model in-process through MAX's `PIPELINE_REGISTRY` pipeline (`max_engine.py`), driven from compiled Mojo;
- reads KV-cache reuse from MAX's real `num_cached_tokens` each turn, prefix caching on, so repeated prefixes are *measured* not estimated;
- lets the model choose tools — schemas go in the request, no `tool_choice` pinning, no keyword pre-decision — keeps the exact `<tool_call>` bytes the model emits, and parses them with EmberJSON behind a typed `ToolCodec`;
- keeps the timeline as a typed `List[SessionEntry]` with an append-only event log and non-destructive compaction;
- gates the refund tool behind a confirmation tied to the specific order id, so a stray "yes" can't approve some other action.

## The one decision everything hangs off

The whole design turns on a single trait that decouples the harness from the model:

```mojo
trait Engine:
    def generate(
        mut self, messages_json: String, tools_json: String, max_new_tokens: Int
    ) raises -> EngineResult: ...

def process_turn[E: Engine](
    mut harness: IgnisCore, mut engine: E, tools: String, user_text: String
) raises -> String:
    ...
```

Two backends satisfy `Engine`:

- **`MaxBackend`** holds a `PythonObject` into `max_engine` and runs the real in-process model.
- **`FixtureBackend`** returns deterministic, canned output — no model, no GPU.

`process_turn[E: Engine]` specializes at compile time, with no dynamic dispatch on the hot path. That's the trick that lets `make test` exercise the *entire* harness — parser, policy, cache-report plumbing, compaction, events — with no model present. The division of ownership is deliberate: **Mojo owns** the timeline, prompt rendering, tool parsing, policy, execution, replay bytes, and telemetry; **MAX owns** model execution, the KV prefix cache, and generated text.

## The architecture, in one diagram

```
                ┌───────────────────────────────────────────────────────┐
   ./ignis CLI  │  retail-fixture | retail-live | coding-* | eval |      │
                │  session-save | session-resume | help                  │
                └───────────────────────────┬───────────────────────────┘
                                            ▼
   ┌──────────────────────  ignis.mojo  (compiled Mojo)  ───────────────────────┐
   │                                                                            │
   │  IgnisCore ── List[SessionEntry]  (typed structs, not parallel columns)    │
   │     ├─ render_messages()     prompt-visible entries → model context bytes   │
   │     ├─ ToolCodec / ToolCall  parse the model's exact <tool_call> bytes      │
   │     │      (ignis_json.mojo, EmberJSON)                                     │
   │     ├─ policy gate           order-id-bound refund confirmation             │
   │     ├─ execute_tool          run the typed call, append the result          │
   │     └─ events / replay_log   append-only: model.cache_report, tool.*,       │
   │                              policy.*  (telemetry, never session truth)     │
   │                                                                            │
   │  process_turn[E: Engine]  ── generic over the backend ─────────────┐       │
   └───────────────────────────────────────────────────────────────┐   │       │
                                                                     ▼   ▼
                                       ┌────────────────┐   ┌────────────────────┐
                                       │ FixtureBackend │   │     MaxBackend     │
                                       │ canned, no GPU │   │ std.python→CPython  │
                                       │ (make test)    │   │ (real model)        │
                                       └────────────────┘   └─────────┬──────────┘
                                                                      ▼
                                                          max_engine.py  (Python)
                                                          PIPELINE_REGISTRY.retrieve
                                                          generate_async + KV cache
                                                                      ▼
                                                    compiled MAX graph + kernels
                                                         (native, on-device)
```

Read it top-down: the CLI selects a scenario; `IgnisCore` owns all the deterministic state and logic; `process_turn` is generic, so the *same* control plane runs over either backend; only `MaxBackend` crosses the `std.python` seam into MAX. The boundary Mojo calls across is deliberately thin — `max_engine.py`'s `generate_raw(...)` is **string-in / compact-JSON-out** (`{text, prompt_tokens, cached_tokens, generated_tokens}`), so nothing about the model leaks into the harness except bytes and honest numbers.

## The control flow of a single turn

A tool turn is **two in-process model calls**, with the policy gate in between. Here is the lifecycle:

```
  user text
     │
     ▼
  append to timeline ─► render_messages() ─► [ model call #1 : messages + tool schemas ]
                                                          │
                                       <tool_call>{json}</tool_call>   (exact bytes kept)
                                                          ▼
                                          ToolCodec.decode → typed ToolCall
                                                          │
                                      ┌───────────────────┴───────────────────┐
                                sensitive tool?                          plain tool
                                      │                                       │
                            policy gate (order-id bound)                      │
                              ├─ denied  → "needs confirmation" reply         │
                              └─ approved│                                    │
                                         ▼                                    ▼
                                    execute_tool ───────────────────►  tool result
                                                          │
                                            append result to timeline
                                                          ▼
                            [ model call #2 : messages + result, NO tools ]
                                                          ▼
                                       user-facing reply   +   appended events
```

Two design choices fall out of this:

1. **Two calls, not one.** Call #1 carries the tool schemas and the model emits a `<tool_call>`; call #2 omits the tools, appends the tool result, and the model writes the customer-facing sentence. They're kept as separate requests so MAX's prefix cache reuses the shared context across both — which is exactly what `num_cached_tokens` shows climbing turn over turn.
2. **The model chooses; the harness decides whether to act.** There is no keyword pre-decision and no `tool_choice` pinning. The harness parses the model's *exact emitted bytes* with EmberJSON into a typed `ToolCall`, then the policy gate runs before any execution. A refund is denied until an explicit confirmation whose `order_id` matches the pending one — a bare "yes" (e.g. inside "yesterday") never approves, and confirming one order never approves another.

## Against the grain of the official path

It helps to see what Ignis is *not*. Modular's own agentic cookbook goes the other way: `max serve` runs the model as a separate process, a Python FastAPI backend talks to it over HTTP through the OpenAI SDK, and no Mojo appears anywhere. The agent loop is ordinary OpenAI function calling — stream chunks, check `finish_reason == "tool_calls"`, run the tool, append, call again. It's clean, practical, and matches how MAX is positioned: serving infrastructure behind an OpenAI-compatible endpoint any provider could stand in for.

Ignis reverses every one of those choices. No `max serve`, no REST hop, a compiled Mojo control plane driving the engine in the same OS process. The cookbook calls MAX as a service; **Ignis runs inside it.** Whether that trade pays off depends on the workload — a web backend serving many users wants the separation (it scales horizontally and is simpler to operate); an experiment in tight Mojo-MAX coupling wants the opposite, and so does the `ds4` design where the session *is* the persisted KV. Ignis is the second kind of program.

## The repo, briefly

- **`ignis.mojo`** — the control plane: `IgnisCore` session state, the `List[SessionEntry]` timeline, prompt rendering, the exact-confirmation policy, tool execution, the CLI, the behavioral eval suite, and a second "coding agent" scenario. The bulk of the code.
- **`ignis_json.mojo`** — the typed tool boundary: `ToolCall`, the `ToolCodec` trait, `HermesToolCodec`, `decode_tool_call[C: ToolCodec]`, all backed by EmberJSON.
- **`max_engine.py`** — the Python side of the in-process bridge. Loads the model via `PIPELINE_REGISTRY.retrieve(...)`, generates with `generate_async(...)`. Its `generate_raw(...)` is the **string-in / string-out** seam Mojo calls across.
- **`max_backend.mojo`** — a standalone, self-contained real-model retail loop (the `make backend-demo` spike). Not part of the `./ignis` binary.
- **`examples/`** — runnable scenarios and extension demos (catalog below).
- **`docs/extensions.md`** — the one tracked doc: how to add tools, policies, backends, and custom ops without breaking Ignis's contracts.

## Extending Ignis

The rule, from `docs/extensions.md`: *extensions may add behavior, but must not bypass the typed `ToolCall`, the policy gate, or the append-only event log.* There are five extension points:

**A tool.** The model picks tools from the schema in `tools_json()`; the `ToolCodec` already decodes any `<tool_call>` into a typed `ToolCall`, so a new tool needs only a schema entry (OpenAI function format), an execution branch in `execute_tool`, optional policy, and an eval invariant. Arguments are read with `call.arg("order_id")` — never substring-scanned.

```mojo
# 1) schema entry in tools_json()  →  2) branch in execute_tool:
def execute_tool(name: String, order_id: String) -> String:
    if name == "lookup_return_window":
        return "Order " + order_id + " has 12 days left in its return window."
```

**A policy gate.** Gates run after parsing and before execution, inside `process_turn`, and must emit enough events to audit both paths. Bind approval to the *exact critical argument* so a generic "yes" cannot approve a different action — the refund gate keys on `order_id`; the `banking_agent` example keys on `from_account:amount` (two fields).

**A backend.** Implement `trait Engine` and return an `EngineResult` with real token stats; `process_turn[E: Engine]` is generic, so nothing else changes. (See `custom_backend` for a remote OpenAI-compatible engine.)

**A custom op — the Mojo-native frontier.** The one extension type where Mojo does work *in the inference hot path*: author a `@compiler.register` kernel and either run it in a graph, or thread it into live generation via `SamplingParams.logits_processors`. (Worked, verified example: `graph_policy_gate`. Depth in [Part 4](./04-max-the-platform.md).)

**Timeline / telemetry.** Append `SessionEntry` values with an explicit `prompt_visible` flag; runtime-only state (cache stats, replay bytes) stays in events and out of the model-visible bytes. Preserve the **byte-identical re-render invariant** — durable session resume depends on `render_messages()` being a pure function of the prompt-visible entries.

## Examples included

Each lives under `examples/` with its own README; the first two are full end-to-end scenarios, the rest are focused extension demos:

- **`retail_recovery`** — the complete vertical slice: real Qwen tool selection, parser-owned execution, the money-impacting refund gate, append-only artifacts. The canonical "what a turn looks like."
- **`coding_agent`** — a real in-process coding agent that `read_file`/`write_file`s a Python workspace and runs its tests until they pass — same harness, same `Engine`/`ToolCodec`/timeline, real cache metrics.
- **`banking_agent`** — extends the policy to bind confirmation to **two fields** (`from_account:amount`): confirming a 100 USD transfer can't approve a 999 USD one. Adds two eval scenarios.
- **`rag_search`** — a read-only `search_docs(query)` tool that delegates to a Python companion via `std.python`; the pattern for tools that need no gate and no harness change. Swap its body for real embeddings and it becomes semantic search.
- **`custom_backend`** — `RemoteBackend` implements `Engine` against any OpenAI-compatible endpoint (max serve, Ollama, OpenAI). Trade-off stated honestly: `cached_tokens` is always 0, because the REST boundary hides `num_cached_tokens` — in-process is the only path to real cache telemetry.
- **`graph_policy_gate`** — the Mojo custom op (`gated_logits`) compiled into a MAX graph and run inside a live Qwen3's sampler. The constrained-decoding frontier, in miniature.
- **`grammar_policy_gate`** — the airtight version riding MAX's own llguidance grammar engine (GPU-only). Together with `graph_policy_gate` it maps the same policy onto two enforcement layers.

## Build it — and don't `mojo run` it

The first thing to internalize, because no type checker will catch it: **Ignis is a build-and-run program, never a `mojo run` program.** Launch anything that drives MAX's engine under JIT and model init crashes with `LLVM ERROR: ... M::Context with different Init::Options`. There is one process-global Modular context, and the JIT runtime and MAX disagree on its options. `mojo build` the binary, run *that*, and it initializes the context in a way MAX accepts. The Makefile always builds first.

The toolchain is the **Mojo 1.0 beta + MAX** Modular nightly (verified build: Mojo `1.0.0b2.dev2026052406` / MAX `26.4.0.dev2026052406`). The `modular` wheel bundles `max`, the `mojo` compiler, and the runtime deps (`huggingface_hub`, `transformers`). Live runs need the MAX venv active so the embedded CPython resolves `max`:

```bash
VIRTUAL_ENV=/path/.venv PATH=/path/.venv/bin:$PATH ./ignis retail-live
```

(New to Mojo or MAX? [Part 3](./03-mojo-the-language.md) and [Part 4](./04-max-the-platform.md) each open with a from-scratch primer.)

## The commands

```bash
make deps            # git-clone EmberJSON into third_party/ (or: pixi install)
make build           # compile ./ignis
make test            # FULL deterministic CI: ToolCodec self-tests + behavioral eval (no model)
make eval            # behavioral eval suite only (no model)  ==  ./ignis eval
make retail-fixture  # retail scenario via FixtureBackend (no model)
make coding-fixture  # coding scenario via FixtureBackend (no model)
make retail-live     # real in-process Qwen3-8B retail scenario (slow, CPU)
make coding-live     # real in-process Qwen3-8B coding scenario
make backend-demo    # standalone max_backend.mojo spike (real model)
```

The compiled CLI is `./ignis <command> [event-log-path]`, where command is `retail-fixture | retail-live | coding-fixture | coding-live | eval | help`. There's no per-test runner: the granularities are `make json-test` (parser self-tests), `make eval` (all behavioral scenarios — non-zero exit unless every one passes), or a single end-to-end scenario via `./ignis retail-fixture`.

## A caution that matters before you read any trace

`make test` writes an `events.log` — but it's the **fixture** run, not a live one. `FixtureBackend` emits the *same event shape* as live on purpose (that's the point of the trait), but its numbers are synthetic: `prompt_tokens` is the literal `200`, `cached_tokens` marches `0/128/256/384`. The `source=max_num_cached_tokens` tag on a cache event is plumbing, not evidence. Real telemetry comes off a live `MaxBackend` run. Never read a fixture trace as live numbers — a discipline that runs through the whole project and is the subject of [Part 2](./02-what-was-achieved.md).

---

*Previous: [The Curiosity and the Plan](./00-curiosity-and-the-plan.md). Next: [What Ignis Achieved](./02-what-was-achieved.md). [Series index](./ignis.md).*
