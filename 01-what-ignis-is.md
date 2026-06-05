---
title: "Part 1 — What It Is, and How to Run It"
nav_order: 2
---

# Ignis — Finding Your Mojo from DwarfStar

## Part 1 — What It Is, and How to Run It

*Part 1 of the Ignis expedition. [Part 0](./00-curiosity-and-the-plan.md) was the why. This is the what: the shape of the repo, the one design decision everything else hangs off, and enough of a user guide to build it and watch it run. If you only read one part to understand the artifact, read this one.*

---

### What Ignis is, in one breath

Ignis is a Mojo-native agent harness that runs the model **in the same OS process** as the control plane. There is no `curl`, no separate `max serve`, no REST hop. Compiled Mojo embeds CPython through `std.python` and drives MAX's in-process pipeline from there. The default model is `Qwen/Qwen3-8B`, loaded and graph-compiled in-process. A deterministic fixture backend runs the *same* harness with no model at all, which is what keeps CI fast and the design honest.

It is not a line-by-line port of [`ds4`](https://github.com/antirez/ds4) — the translation is architectural. Concretely, Ignis:

- runs the model in-process through MAX's `PIPELINE_REGISTRY` pipeline (`max_engine.py`), driven from compiled Mojo;
- reads KV-cache reuse from MAX's real `num_cached_tokens` each turn, prefix caching on, so repeated prefixes are *measured* not estimated;
- lets the model choose tools — schemas go in the request, no `tool_choice` pinning, no keyword pre-decision — keeps the exact `<tool_call>` bytes the model emits, and parses them with EmberJSON behind a typed `ToolCodec`;
- keeps the timeline as a typed `List[SessionEntry]` with an append-only event log and non-destructive compaction;
- gates the refund tool behind a confirmation tied to the specific order id, so a stray "yes" can't approve some other action.

### The one decision everything hangs off

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

One more shape worth knowing: **a tool turn is two in-process model calls.** (1) with tool schemas → the model's `<tool_call>`; (2) without tools, with the tool result appended → the user-facing reply. Prefix caching reuses the shared context across both, which is why they're kept as separate requests.

### Against the grain of the official path

It helps to see what Ignis is *not*. Modular's own agentic cookbook goes the other way: `max serve` runs the model as a separate process, a Python FastAPI backend talks to it over HTTP through the OpenAI SDK, and no Mojo appears anywhere. The agent loop is ordinary OpenAI function calling — stream chunks, check `finish_reason == "tool_calls"`, run the tool, append, call again. It's clean, practical, and matches how MAX is positioned: serving infrastructure behind an OpenAI-compatible endpoint any provider could stand in for.

Ignis reverses every one of those choices. No `max serve`, no REST hop, a compiled Mojo control plane driving the engine in the same OS process. The cookbook calls MAX as a service; **Ignis runs inside it.** Whether that trade pays off depends on the workload — a web backend serving many users wants the separation (it scales horizontally and is simpler to operate); an experiment in tight Mojo-MAX coupling wants the opposite, and so does the `ds4` design where the session *is* the persisted KV. Ignis is the second kind of program.

### The repo, briefly

- **`ignis.mojo`** — the control plane: `IgnisCore` session state, the `List[SessionEntry]` timeline, prompt rendering, the exact-confirmation policy, tool execution, the CLI, the behavioral eval suite, and a second "coding agent" scenario. The bulk of the code.
- **`ignis_json.mojo`** — the typed tool boundary: `ToolCall`, the `ToolCodec` trait, `HermesToolCodec`, `decode_tool_call[C: ToolCodec]`, all backed by EmberJSON.
- **`max_engine.py`** — the Python side of the in-process bridge. Loads the model via `PIPELINE_REGISTRY.retrieve(...)`, generates with `generate_async(...)`. Its `generate_raw(...)` is a **string-in / string-out** boundary returning compact JSON (`{text, prompt_tokens, cached_tokens, generated_tokens}`) — the seam Mojo calls across.
- **`max_backend.mojo`** — a standalone, self-contained real-model retail loop (the `make backend-demo` spike). Not part of the `./ignis` binary.

### Build it — and don't `mojo run` it

The first thing to internalize, because no type checker will catch it: **Ignis is a build-and-run program, never a `mojo run` program.** Launch anything that drives MAX's engine under JIT and model init crashes with `LLVM ERROR: ... M::Context with different Init::Options`. There is one process-global Modular context, and the JIT runtime and MAX disagree on its options. `mojo build` the binary, run *that*, and it initializes the context in a way MAX accepts. The Makefile always builds first.

The toolchain is the **Mojo 1.0 beta + MAX** Modular nightly (verified build: Mojo `1.0.0b2.dev2026052406` / MAX `26.4.0.dev2026052406`). The `modular` wheel bundles `max`, the `mojo` compiler, and the runtime deps (`huggingface_hub`, `transformers`). Live runs need the MAX venv active so the embedded CPython resolves `max`:

```bash
VIRTUAL_ENV=/path/.venv PATH=/path/.venv/bin:$PATH ./ignis retail-live
```

### The commands

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

### A caution that matters before you read any trace

`make test` writes an `events.log` — but it's the **fixture** run, not a live one. `FixtureBackend` emits the *same event shape* as live on purpose (that's the point of the trait), but its numbers are synthetic: `prompt_tokens` is the literal `200`, `cached_tokens` marches `0/128/256/384`. The `source=max_num_cached_tokens` tag on a cache event is plumbing, not evidence. Real telemetry comes off a live `MaxBackend` run. Never read a fixture trace as live numbers — a discipline that runs through the whole project and is the subject of [Part 2](./02-what-was-achieved.md).

---

---

*Previous: [The Curiosity and the Plan](./00-curiosity-and-the-plan.md). Next: [What Ignis Achieved](./02-what-was-achieved.md). [Series index](./index.md).*
