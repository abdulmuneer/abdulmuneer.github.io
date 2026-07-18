---
title: "Part 2 - What Was Achieved"
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-ember.svg
sidebar:
  nav: "ignis"
---

*Part 2. [Part 0](./00-curiosity-and-the-plan.md) laid out a plan, M0 through M5. This part grades it against what's actually verified, headline result first, with the things I didn't measure stated as plainly as the things I did. The deep mechanics are in [Part 4](./04-max-the-platform.md); this is the scorecard.*

## A conversation that survives its own process

The most distinctive thing Ignis does is durable session resume. One process holds a conversation and saves; a separate process loads it and continues, with the model's KV warm:

```
SESSION_RESUME_OK kv_warmstart_tokens=1152
```

A fresh process, 1152 tokens of the restored conversation served from disk, the model picking up where the killed process left off. Resume, not replay. This is the `ds4` line - "the session is the on-disk KV" - turned into a feature.

It helps to split this into two halves. MAX's half: its tiered connector writes KV blocks to disk and addresses them by a hash of the token prefix, not by any session id. Send it a matching prefix and it serves those blocks back. It does not store your messages, and it has no idea that one process is continuing another's conversation - by design, an inference engine shouldn't. Ignis's half is the binding MAX leaves to the caller. It persists the conversation timeline and re-renders it to byte-identical tokens, so the prefix hashes to the same key and a fresh process reuses the on-disk KV instead of re-running prefill. That byte-identical re-render is the whole trick; everything else here is a careful assembly of MAX primitives. (The mechanics, and the three `TieredConnector` bugs it works around, are in Parts [4](./04-max-the-platform.md) and [5](./05-the-journey.md).)

## The development milestones

The roadmap ran M0 (control plane) → M1 (real repo) → M2 (real MAX) → M3 (the `ds4` lesson) → M4 (Mojo in the graph) → M5 (deeper integration). Here's where each landed.

| Milestone | Status | What's verified |
|---|---|---|
| **M0** control plane | ✅ done | Typed `List[SessionEntry]` timeline, tool parsing, policy gate, the `Engine` trait + `FixtureBackend`. |
| **M1** real repo | ✅ done | Makefile, docs, fixtures, model-free CI green (`make test`; the eval has since grown to 19 scenarios). |
| **M2** real MAX | ✅ **exceeded** | Not a non-streaming *endpoint* - the model runs in-process, the strongest form of M2. Real prefix-cache reuse measured per turn. |
| **M3** the `ds4` lesson | ✅ mostly | Exact model-emitted `<tool_call>` bytes stored and replayed; a real cache report every turn. |
| **M4** Mojo in the graph | ✅ done (with a ceiling) | A Mojo custom op was compiled into the MAX graph and ran inside the live sampler; a grammar-constrained tool-name gate via MAX's own engine. See [Part 4](./04-max-the-platform.md). |
| **M5** deeper integration | ✅ the novel slice | Durable session resume across processes (above). Custom-architecture work left for later. |

The one to notice is M2. The plan hedged toward a non-streaming MAX endpoint; what shipped puts the model in the harness's own process. That single change is what makes the rest possible - reading MAX's real cache numbers directly, keeping the model's exact bytes without an OpenAI-JSON round trip, and binding a durable conversation to durable KV.

## The numbers

Because the model is in-process, Ignis reads cache reuse straight off MAX's `num_cached_tokens` and logs it unchanged. From a live Qwen3-8B run with prefix caching on (these are `MaxBackend` numbers, not the fixture):

```
turn1: prompt_tokens=214 cached_tokens=0   generated=29
turn2: prompt_tokens=256 cached_tokens=128 generated=29
turn3: prompt_tokens=296 cached_tokens=256 generated=38
```

The figure behaves like a real systems number, with one wrinkle worth naming: `num_cached_tokens` is page-granular. Reuse comes back in multiples of the cache page size (128 here, from the `0 → 128 → 256` deltas), so `cached_tokens` is the shared prefix floored to a page boundary, and it's always `<= prompt_tokens`. Ignis logs it exactly as MAX reports it, and never rounds up to imply more reuse than actually happened.

The model participates for real, too. In a live retail run, Qwen3 chose `get_order_status` for an order question and `issue_refund_quote` for a refund, filled `order_id` and `reason` from the customer's words, and the confirmation gate held - refund denied until the customer confirmed the matching order, then approved:

```
turn1 order   -> model chose get_order_status   (cached_tokens=0)   -> allowed
turn2 refund  -> model chose issue_refund_quote (cached_tokens=256) -> DENIED
turn3 confirm -> model chose issue_refund_quote (cached_tokens=256) -> APPROVED
```

The gate holds because approval is bound to the exact order id the customer named: confirming one order can never release a refund on another.

## The custom-op result

This is detailed in [Part 4](./04-max-the-platform.md), but in short:

- **A Mojo custom op runs in the MAX graph.** `gated_logits` (`@compiler.register`, `def execute`) compiles in and enforces the refund gate as a graph node - and runs inside a live Qwen3's decode loop through `SamplingParams.logits_processors`. Gate closed, the model can't spell the refund tool. Verified (`GATE_OP_DEMO_OK`, `LIVE_GATE_OK`).
- **The grammar-constrained version uses MAX's own engine.** A `response_format` enum chosen by the policy excludes the refund tool name through llguidance. Verified on H100 (`GRAMMAR_GATE_OK`).

## Four additional results

After M5, four questions still required code and verification.

**A second pipeline in the same process.** The in-process bet was proven for one model. Real retrieval needs a second one - an embedder - and the obvious worry was that process-global Modular context again, the thing that crashes `mojo run`. Would a second pipeline collide with the first the same way? It doesn't. An embedding pipeline (`task=PipelineTask.EMBEDDINGS_GENERATION`, mpnet on CPU) and the Qwen3 LLM (GPU) load and run in one OS process with no `M::Context` conflict. The index itself stays on the Mojo side - a flat `Float32` buffer ranked by a SIMD dot-product top-k kernel in `ignis_vec.mojo` - which is the first place Mojo does real application compute here, not just glue. Live on an H100, the model wrote its own search queries and the embedder put the right document first on both turns. The behavioral eval grew from 9 to 19 scenarios, still all model-free.

**A durable retrieval program.** The semantic path above proved two MAX
pipelines and a Mojo ranking kernel, but its small corpus was rebuilt for each
run. The `rag_search` example now also indexes arbitrary local documentation in
SQLite FTS5 and keeps it across restarts. Full and scoped refreshes are atomic
and incremental. Results include line citations, source hashes and versions,
stable chunk ids, and a snapshot id read in the same transaction; zero results
retain that snapshot id. The Python API, CLI, read-only Mojo bridge, and
authenticated loopback HTTP adapter share the same contract. Files, corpus
size, queries, responses, connections, workers, and timeouts are bounded.
`KNOWLEDGE_BASE_OK`, `KNOWLEDGE_INTERFACES_OK`, and `KNOWLEDGE_BRIDGE_OK` cover
the lifecycle and the actual interfaces, including corrupt databases, symlink
components, malformed HTTP, redacted logs, graceful shutdown, and concurrent
WAL indexing.

**Speculative decoding, and an honest loss.** One of the things we really want from the agent loop is lower latency, and MAX advertises speculative decoding: a small draft model proposes *k* tokens and the big target verifies them in a single pass. Getting Qwen3-0.6B to draft for Qwen3-8B took three source patches to MAX 26.4 (the details are in [Part 4](./04-max-the-platform.md)). Then I benchmarked it - greedy, three 256-token runs after warm-up - and it lost: baseline **165.7 tok/s**, spec k=2 **141.6 tok/s**. Each verify cycle carries about 5.5 ms of host-side overhead in MAX's pipeline, and break-even at k=2 needs roughly 2.4 accepted tokens per cycle where this pair delivers 2.15. With a synthetic 100% acceptance the ceiling climbs to 305.8 tok/s at k=5, so the machinery does pay off - for bigger, slower targets, just not at 8B. It ships opt-in (`IGNIS_DRAFT_MODEL`), off by default, with the warning attached.

**Measuring accuracy.** The milestones show the harness runs; they say nothing about how good the agent is - how often the model picks the right tool, fills the right arguments, and stays inside the policy. `eval-live` measures that. It runs the real model over paraphrase buckets (the same request phrased many ways) for tool selection, gate discipline, retrieval grounding, spec fetching, and off-script safety, and grades each run from the typed tool call and policy events it produced: did the model call `issue_refund_quote`, did the gate deny then approve, did the embedder surface the right document. Because the boundary is typed, each grade is a plain assertion against what the model emitted, with no second model judging the first. With Qwen3-8B it sits at 19/19 today. It writes a report and always exits 0.

## What I did NOT measure

A scorecard that only lists wins is marketing. So, plainly:

- **One benchmark, not a performance study.** The speculative-decoding numbers above are the project's only wall-clock measurement, and they report a loss. 
- **Count, not latency, for cache reuse.** I measured the count of reused tokens (`num_cached_tokens`, and the 1152 warm-start tokens off disk), never the wall-clock or cost that reuse saves.
- **The confirmation signal is a coarse keyword check.** The order-id binding
  is the enforcement mechanism; the language matcher is not a general intent
  classifier.
- **The live logit-gate was checked on the 0.6B**, which shares the Qwen3 tokenizer with the 8B (identical token ids, identical enforcement) and iterates in seconds.
- **The durable search checks correctness, not ranking quality or throughput.**
  Its ranker is lexical BM25. I did not benchmark a large corpus, compare search
  relevance, or test hostile multi-user load. The HTTP adapter is deliberately
  loopback-only and single-user.

Read against those caveats, the result is narrow but solid: a compiled,
deterministic in-process harness with real cache telemetry, byte-exact tool
replay, policy enforcement in the decode loop, semantic retrieval through a
second MAX pipeline, durable cited local search, and cross-process conversation
resume. Each path has a model-free verification layer. It is not the drop-in
replacement proposed in [Part 0](./00-curiosity-and-the-plan.md).

---

*Previous: [What Ignis Is](./01-what-ignis-is.md). Next: [Mojo, the Language](./03-mojo-the-language.md). [Series index](./ignis.md).*
