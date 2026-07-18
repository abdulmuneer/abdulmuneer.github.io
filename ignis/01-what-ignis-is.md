---
title: "Part 1 - What It Is, and How to Run It"
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-ember.svg
sidebar:
  nav: "ignis"
---

*Part 1. [Part 0](./00-curiosity-and-the-plan.md) was the why; this is the what. The shape of the repo, the one design decision the rest hangs off, what a single turn does, how to extend it, and how to build and run it. If you only read one part, read this one.*

<p style="text-align:center"><img class="brand-logo" src="/assets/images/ignis-process.svg" alt="Harness and model in one OS process" style="width:560px;max-width:100%"></p>



## What Ignis is:

Ignis is a Mojo-native agent harness that runs the model in the same OS process as the control plane: no `curl`, no separate `max serve`, no REST hop. Compiled Mojo embeds CPython through `std.python` and drives MAX's in-process pipeline from there. The default model is `Qwen/Qwen3-8B`, loaded and graph-compiled in-process. The same control-plane code also runs against a fixture backend with no model at all, which is what the test suite uses.

It isn't a port of [`ds4`](https://github.com/antirez/ds4); the translation is architectural. Concretely, Ignis:

- runs the model in-process through MAX's `PIPELINE_REGISTRY` pipeline (`max_engine.py`), driven from compiled Mojo;
- reads KV-cache reuse off MAX's real `num_cached_tokens` each turn, prefix caching on, so repeated prefixes are measured rather than estimated;
- lets the model choose tools - schemas go in the request, no `tool_choice` pinning, no keyword pre-decision - keeps the exact `<tool_call>` bytes it emits, and parses them with EmberJSON behind a typed `ToolCodec`;
- keeps the timeline as a typed `List[SessionEntry]` with an append-only event log and non-destructive compaction;
- gates the refund tool behind a confirmation tied to the specific order id, so a stray "yes" can't approve some other action;
- runs a second MAX pipeline - an embedding model - in the same process, with retrieval ranked by a Mojo SIMD vector index.

## The one decision everything hangs off

The whole design turns on one trait that decouples the harness from the model:

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
- **`FixtureBackend`** returns deterministic canned output. No model inference involved.

`process_turn[E: Engine]` specializes at compile time, so there's no dynamic dispatch on the hot path and the same control-plane code runs over either backend. That's what lets `make test` exercise the entire harness - parser, policy, cache-report plumbing, compaction, events - with no model present.

## The architecture

```
                ┌───────────────────────────────────────────────────────┐
   ./ignis CLI  │  retail-fixture | retail-live | coding-* | rag-* |    │
                │  nav-* | eval | session-save | session-resume | help  │
                └───────────────────────────┬───────────────────────────┘
                                            ▼
   ┌──────────────────────  ignis.mojo  (compiled Mojo)  ───────────────────────┐
   │                                                                            │
   │  IgnisCore ── List[SessionEntry]  (typed structs, not parallel columns)    │
   │     ├─ render_messages()     prompt-visible entries → model context bytes  │
   │     ├─ ToolCodec / ToolCall  parse the model's exact <tool_call> bytes     │
   │     │      (ignis_json.mojo, EmberJSON)                                    │
   │     ├─ policy gate           order-id-bound refund confirmation            │
   │     ├─ execute_tool          run the typed call, append the result         │
   │     └─ events / replay_log   append-only: model.cache_report, tool.*,      │
   │                              policy.*  (telemetry, never session truth)    │
   │                                                                            │
   │  process_turn[E: Engine]  ── generic over the backend ─────────────┐       │
   └───────────────────────────────────────────────────────────────┐   │        │
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

Read it top-down: the CLI picks a scenario; `IgnisCore` owns the deterministic state and logic; `process_turn` is generic, so the same control plane runs over either backend; only `MaxBackend` crosses the `std.python` seam into MAX.

That seam is the division of ownership the whole design rests on. Above it, Mojo owns the timeline, prompt rendering, tool parsing, policy, execution, replay bytes, and telemetry. Below it, MAX owns model execution, the KV prefix cache, and generated text. The boundary is kept thin on purpose: `max_engine.py`'s `generate_raw(...)` is string-in, compact-JSON-out (`{text, prompt_tokens, cached_tokens, generated_tokens}`), so nothing about the model leaks into the harness except bytes and numbers.

## The control flow of a single turn

The flow is easier to read against a concrete scenario, so take the retail agent (the `retail_recovery` example): a customer-support assistant that looks up orders and issues refund quotes. The customer types a message, and the harness runs two in-process model calls with the policy gate in between:

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

Two choices fall out of this.

First, two calls, not one. Call #1 carries the tool schemas and the model emits a `<tool_call>`; call #2 drops the tools, appends the tool result, and the model writes the customer-facing sentence. They stay separate requests so MAX's prefix cache reuses the shared context across both - which is what `num_cached_tokens` shows climbing turn over turn.

Second, the model chooses; the harness decides whether to act. No keyword pre-decision, no `tool_choice` pinning. The harness parses the model's exact emitted bytes into a typed `ToolCall`, and the policy gate runs before any execution. A refund is denied until a confirmation whose `order_id` matches the pending one. A bare "yes" - say, inside "yesterday" - never approves, and confirming one order never approves another.

## Against the grain of the official path

It helps to see what Ignis is *not*. Modular's own agentic cookbook goes the other way: `max serve` runs the model as a separate process, a Python FastAPI backend talks to it over HTTP through the OpenAI SDK, and no Mojo appears anywhere. The agent loop is OpenAI function calling - stream chunks, check `finish_reason == "tool_calls"`, run the tool, append, call again. It's clean, practical, and it matches how MAX is positioned: serving infrastructure behind an OpenAI-compatible endpoint that any provider could stand in for.

Ignis reverses those choices. No `max serve`, no REST hop, a compiled Mojo control plane driving the engine in the same OS process. The cookbook calls MAX as a service; Ignis runs inside it. Which trade is right depends on the workload. A web backend serving many users wants the separation - it scales horizontally and is simpler to operate. An experiment in tight Mojo-MAX coupling wants the opposite, and so does the `ds4` design where the session *is* the persisted KV. Ignis is the second kind of program.

## The repo

- **`ignis.mojo`** - the control plane: `IgnisCore` session state, the `List[SessionEntry]` timeline, prompt rendering, the exact-confirmation policy, tool execution, the CLI, the behavioral eval suite, and the coding / RAG / api-navigator scenarios. Most of the code lives here.
- **`ignis_json.mojo`** - the typed tool boundary: `ToolCall`, the `ToolCodec` trait, `HermesToolCodec`, `decode_tool_call[C: ToolCodec]`, all backed by EmberJSON.
- **`ignis_vec.mojo`** - the retrieval plane: the `Embedder` trait, a flat-buffer `VectorIndex` ranked by a SIMD dot-product top-k kernel, and a deterministic `FixtureEmbedder`. The first pure-Mojo compute in Ignis that's load-bearing rather than a demo.
- **`max_engine.py`** - the Python side of the bridge. Loads the model via `PIPELINE_REGISTRY.retrieve(...)`, generates with `generate_async(...)`. Its `generate_raw(...)` is the string-in/string-out seam Mojo calls across; `EmbedEngine` opens the same seam for the embedding pipeline.
- **`max_backend.mojo`** - a standalone real-model retail loop (`make backend-demo`). Not part of the `./ignis` binary.
- **`examples/`** - runnable scenarios and extension demos (catalog below).
- **`docs/extensions.md`** - the one tracked doc: how to add tools, policies, backends, and custom ops without breaking the contracts.

A good way to read the repo: start with retail_recovery to see a complete turn, read docs/extensions.md for the seams and the contract, then treat each remaining example as the worked answer to "how do I actually add one of these seams?"

## Extending Ignis

The rule, from `docs/extensions.md`: an extension may add behavior, but it must not bypass the typed `ToolCall`, the policy gate, or the append-only event log. There are six extension points.

**A tool.** The model picks tools from the schema in `tools_json()`; the `ToolCodec` already decodes any `<tool_call>` into a typed `ToolCall`, so a new tool needs only a schema entry (OpenAI function format), a branch in `execute_tool`, optional policy, and an eval invariant. Arguments come from `call.arg("order_id")`, never a substring scan.

```mojo
# 1) schema entry in tools_json()  →  2) branch in execute_tool:
def execute_tool(name: String, order_id: String) -> String:
    if name == "lookup_return_window":
        return "Order " + order_id + " has 12 days left in its return window."
```

A tool's *result* is a consequence report, not an echo. `write_file` hands back a measured line diff plus a parse triage - a `MUST FIX` line leads the result when the written file no longer parses - and `read_file` returns numbered, windowed lines. Two constraints hold for any result you add: it has to render deterministically (no timestamps, no unsorted output), because durable session resume depends on a byte-identical re-render; and any model-controlled argument that reaches the filesystem or a shell passes an allowlist validator first.

**A policy gate.** Gates run after parsing and before execution, inside `process_turn`, and emit enough events to audit both paths. Bind approval to the exact critical argument so a generic "yes" can't approve a different action - the refund gate keys on `order_id`; the `banking_agent` example keys on `from_account:amount`.

**A backend.** Implement `trait Engine`, return an `EngineResult` with real token stats, and you're done; `process_turn[E: Engine]` is generic. (See `custom_backend` for a remote OpenAI-compatible engine.)

**An embedder.** Retrieval mirrors the backend pattern with a second trait: implement `Embedder` (`MaxEmbedder` bridges to the in-process embedding pipeline; `FixtureEmbedder` gives deterministic vectors for model-free CI) and the Mojo `VectorIndex` ranks whatever it returns. One invariant: vectors are L2-normalized at the boundary, so the SIMD dot product *is* cosine similarity.

**A context tier.** Curated knowledge fetched on demand (`get_capability_info` specs) or a raw escape-hatch corpus mined with grep (`api_navigator`). The rule that makes these safe with a live KV cache: the resident prompt stays byte-stable and discovery arrives as appended tool results - never a mid-session schema or system-prompt mutation, which would invalidate the prefix.

**A custom op.** The one extension type where Mojo does work in the inference hot path: author a `@compiler.register` kernel and either run it in a graph or thread it into live generation via `SamplingParams.logits_processors`. Worked example: `graph_policy_gate`. Depth in [Part 4](./04-max-the-platform.md).

## Examples included

Each example lives under `examples/` with its own README, and they split into two kinds.

**Use-case slices** - the same harness pointed at a different domain, to show the control plane isn't domain-specific:

- **`retail_recovery`** - A customer-support agent that answers order-status questions and issues refund quotes, holding any refund until the customer confirms the exact order. *The full vertical slice: real Qwen tool selection, parser-owned execution, the money-impacting refund gate, append-only artifacts. The canonical "what a turn looks like."*
- **`coding_agent`** - A coding agent that repairs a failing Python test suite by reading and editing files until the tests pass. *Same harness, `Engine`, `ToolCodec`, and timeline as the retail agent. Writes come back as a diff with a MUST FIX triage, so the model sees what it changed and what now looks broken.*

**Extension implementations** - each one is the worked answer to "how do I add a single seam from `docs/extensions.md`?", tagged here with the seam it fills:

- **`banking_agent`** *(policy gate)* - A banking agent that checks balances and transfers funds, with every transfer gated behind an exact confirmation. Binds confirmation to two fields (`from_account:amount`), so confirming a 100 USD transfer can't approve a 999 USD one.
- **`rag_search`** *(retrieval and local service)* - A persistent, model-free
  document index for real Markdown, reStructuredText, and text trees. It uses
  SQLite FTS5, atomic and incremental snapshots, stable line citations, and
  Python and CLI indexing/search interfaces, plus read-only Mojo and
  authenticated loopback HTTP interfaces. The
  separate `./ignis rag-live` path remains the semantic example: a second MAX
  pipeline produces embeddings and Mojo ranks them with a SIMD vector index.
- **`api_navigator`** *(context tier)* - An API-reference agent that answers signature questions by grepping a raw source tome it could never fit in a prompt - live, the installed `max` package itself. A short skill prompt plus two read-only, validated tools, instrumented so the event log shows what the curated tiers are missing.
- **`custom_backend`** *(backend)* - Not an agent but a drop-in engine: it runs the whole harness against any OpenAI-compatible endpoint (`max serve`, Ollama, OpenAI). `cached_tokens` reads 0 in this backend because it doesn't parse the server's usage field; a server like `max serve` can surface cache reuse over REST through OpenAI's `usage.prompt_tokens_details.cached_tokens`, but you're at the server's mercy for whether it does, and at OpenAI's coarser accounting. In-process hands you MAX's own page-granular `num_cached_tokens` directly.
- **`graph_policy_gate`** *(custom op)* - Compiles the refund gate into the model's own decoding as a Mojo custom op, so the forbidden tool can't even be spelled. `gated_logits` compiled into a MAX graph and run inside a live Qwen3's sampler.
- **`grammar_policy_gate`** *(grammar constraint)* - Excludes the refund tool from the allowed tool-name grammar by using MAX's llguidance engine (GPU-only). Same policy as `graph_policy_gate`, enforced during decoding.

### Running the durable knowledge search

This path needs neither model weights nor a network. Give it a source directory
and a private database path:

```bash
export KB_ROOT=/absolute/path/to/docs
export KB_DB=/absolute/path/to/private-state/knowledge.sqlite3

pixi run knowledge index --root "$KB_ROOT" --db "$KB_DB"
pixi run knowledge search --root "$KB_ROOT" --db "$KB_DB" \
  "rollback recovery" --top-k 5
pixi run knowledge status --root "$KB_ROOT" --db "$KB_DB" --json
```

`index` without a path reconciles the whole tree, including deletions. A scoped
file or directory refresh changes only that existing scope. The indexer hashes
source bytes, retains unchanged chunks, prepares the candidate corpus before it
mutates SQLite, and commits documents, FTS rows, and snapshot metadata in one
transaction. Every search result carries a root-relative `path:start-end`
citation, source hash and version, chunk id, and the snapshot id read in the
same transaction. An empty result still identifies the snapshot searched.

The Python `KnowledgeBase` class is the full API. A read-only Mojo client calls
the same implementation through an explicit module path:

```bash
pixi run mojo build examples/rag_search/knowledge_bridge.mojo \
  -o /tmp/ignis-knowledge-bridge
IGNIS_RAG_PYTHONPATH="$(pwd)/examples/rag_search" \
  /tmp/ignis-knowledge-bridge "$KB_ROOT" "$KB_DB" "rollback recovery" 5
```

For a local sidecar, generate `IGNIS_RAG_API_TOKEN` with Python's `secrets`
module and run `pixi run knowledge serve --root "$KB_ROOT" --db "$KB_DB"`.
The server refuses non-loopback binds and exposes only health, readiness,
status, and search. It has bounded bodies, results, connections, workers, and
timeouts. It is a single-user local service, not an internet-facing server.

The filesystem reader rejects outside-root scopes and symlink components,
accepts strict UTF-8 only, and enforces file, corpus, query, and result limits.
The SQLite database contains plaintext source chunks. Keep it in a private
directory and use SQLite's online backup API rather than copying a live WAL
database file. The example README documents permissions, restore, corruption
rebuild, and the exact failure contract.


## Building Ignis from source

Ignis is a build-and-run program (as against `mojo run`). Launch anything that drives MAX's engine under JIT and model init crashes with `LLVM ERROR: ... M::Context with different Init::Options`. There's one process-global Modular context, and the JIT runtime and MAX disagree on its options. `mojo build` the binary, run that, and the context comes up in a way MAX accepts. The Makefile always builds first.

The toolchain is the Mojo 1.0 beta + MAX Modular nightly (the build I worked against: Mojo `1.0.0b2.dev2026052406` / MAX `26.4.0.dev2026052406`). The `modular` wheel bundles `max`, the `mojo` compiler, and the runtime deps (`huggingface_hub`, `transformers`). Live runs need the MAX venv active so the embedded CPython resolves `max`:

```bash
VIRTUAL_ENV=/path/.venv PATH=/path/.venv/bin:$PATH ./ignis retail-live
```

(New to Mojo or MAX? [Part 3](./03-mojo-the-language.md) and [Part 4](./04-max-the-platform.md) each open with a from-scratch primer.)

## The commands

```bash
make deps            # git-clone EmberJSON into third_party/ (or: pixi install)
make build           # compile ./ignis
make test            # deterministic CI: ToolCodec + VectorIndex self-tests + behavioral eval (no model)
make examples-test   # runnable banking, remote-backend, and durable retrieval contracts
make eval            # behavioral eval suite only (no model)  ==  ./ignis eval
make retail-fixture  # retail scenario via FixtureBackend (no model)
make coding-fixture  # coding scenario via FixtureBackend (no model)
make rag-fixture     # in-process RAG scenario via fixtures (no model)
make nav-fixture     # L3 api-navigator scenario over the fixture tome (no model)
make retail-live     # real in-process Qwen3-8B retail scenario
make rag-live        # real RAG: Qwen3-8B + an in-process embedding model, one process
make eval-live       # accuracy tier: real model over paraphrase buckets, graded from typed calls/events
make backend-demo    # standalone max_backend.mojo (real model)
```

The compiled CLI is `./ignis <command> [event-log-path]`. There's no per-test runner: the granularities are `make json-test` (parser self-tests), `make vec-test` (the SIMD index self-tests), `make eval` (every behavioral scenario, non-zero exit unless they all pass), or a single end-to-end scenario like `./ignis retail-fixture`.

One opt-in worth knowing about: live runs accept `IGNIS_DRAFT_MODEL=Qwen/Qwen3-0.6B` to turn on MAX's standalone speculative decoding. It works - and for this model pair it's a measured net slowdown, so it stays off by default. Benchmark your own pair with `scripts/bench_speculative.py` first; [Part 4](./04-max-the-platform.md) has the numbers.

{: .notice--warning}
**Don't read a fixture trace as live numbers.** `make test` writes an `events.log`, but it's the fixture run. `FixtureBackend` emits the same event shape as live - that's the point of the trait - but the numbers are synthetic (`prompt_tokens` is the literal `200`; `cached_tokens` marches `0/128/256/384`). Real telemetry only comes off a live `MaxBackend` run. The same discipline runs through [Part 2](./02-what-was-achieved.md).

---

*Previous: [The Curiosity and the Plan](./00-curiosity-and-the-plan.md). Next: [What Was Achieved](./02-what-was-achieved.md). [Series index](./ignis.md).*
