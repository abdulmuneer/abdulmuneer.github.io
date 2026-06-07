---
title: "Part 2 — What Was Achieved"
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-ember.svg
sidebar:
  nav: "ignis"
---

*Part 2 of the Ignis expedition. [Part 0](./00-curiosity-and-the-plan.md) laid out a plan, M0 through M5. This part grades it — honestly, against what's actually verified, with the headline result first and the things I did **not** measure stated as plainly as the things I did. The deep mechanics live in [Part 4](./04-max-the-platform.md); this is the scorecard.*


## The headline: a conversation that survives its own process

The single most distinctive thing Ignis does — the one capability a stateless REST server cannot offer and that MAX does not hand you — is **durable session resume**. One process holds a conversation and saves; a *separate* process loads it and continues, with the model's KV warm:

```
SESSION_RESUME_OK kv_warmstart_tokens=1152
```

A fresh process, 1152 tokens of the restored conversation served from disk, the model picking up where the killed process left off — **resume, not replay.** This is the `ds4` line, "the session is the on-disk KV," made into a feature.

Why it's the headline: MAX's tiered connector persists KV blocks to disk keyed by token-prefix hash, and a fresh process reuses them if it sends a matching prefix. But MAX has **no concept of a conversation** — it doesn't store your message history and doesn't know a new process is the same session as a dead one. So the harness owns the binding: it persists its timeline and restores it so the re-rendered prompt is *byte-identical*, reproducing the exact token prefix the on-disk KV was keyed on. Everything else in Ignis is a competent assembly of MAX primitives; this is the part where the harness adds something MAX deliberately leaves to you. (The mechanics, and the three `TieredConnector` bugs it works around, are in [Part 4](./04-max-the-platform.md) and [Part 5](./05-the-journey.md).)

## The scorecard against "The Plan"

In [Part 0](./00-curiosity-and-the-plan.md) the roadmap ran M0 (control plane) → M1 (real repo) → M2 (real MAX) → M3 (the `ds4` lesson) → M4 (Mojo in the graph) → M5 (deeper integration). Here's where each landed.

| Milestone | Status | What's verified |
|---|---|---|
| **M0** control plane | ✅ done | Typed `List[SessionEntry]` timeline, tool parsing, policy gate, the `Engine` trait + `FixtureBackend`. |
| **M1** real repo | ✅ done | Makefile, docs, fixtures, model-free CI green (`make test`, eval 9/9). |
| **M2** real MAX | ✅ **exceeded** | Not a non-streaming *endpoint* — the model runs **in-process**, the strongest form of M2. Real prefix-cache reuse measured per turn. |
| **M3** the `ds4` lesson | ✅ mostly | Exact model-emitted `<tool_call>` bytes stored + replayed; a real cache-identity report every turn. |
| **M4** Mojo in the graph | ✅ done (with an honest ceiling) | A Mojo custom op compiled into the MAX graph and run *inside the live sampler*; an airtight grammar gate via MAX's own engine. See [Part 4](./04-max-the-platform.md). |
| **M5** deeper integration | ✅ the novel slice | **Durable session resume across processes** (above). Custom-architecture work left for later. |

The thing to notice: **M2 went further than planned.** The plan hedged toward a non-streaming MAX *endpoint*; what shipped puts the model in the harness's own process. That single change is what makes every other result possible — reading MAX's real cache numbers directly, keeping the model's exact bytes without an OpenAI-JSON round trip, and binding a durable conversation to durable KV.

## Real numbers, measured not invented

Because the model is in-process, Ignis reads cache reuse straight off MAX's `num_cached_tokens` and logs it unmodified. From a live in-process Qwen3-8B run with prefix caching on (these are `MaxBackend` numbers, not the fixture):

```
turn1: prompt_tokens=214 cached_tokens=0   generated=29
turn2: prompt_tokens=256 cached_tokens=128 generated=29
turn3: prompt_tokens=296 cached_tokens=256 generated=38
```

The figure behaves like a real systems number, with one caveat I want to be exact about: `num_cached_tokens` is **page-granular**. Reuse comes back in multiples of the cache page size (128 on this run, inferred from the `0 → 128 → 256` deltas), so `cached_tokens` is the shared prefix *floored to a page boundary*, and it's always `<= prompt_tokens`. Ignis logs it as-is and never rounds up. The old harness this replaced fabricated cache math (`cached_chars = prompt_chars - 160`) and emitted fake `checkpoint_saved`/`.kvmeta` events; a `grep` for any of that over a live log now returns zero. That de-fabrication is itself one of the achievements.

The model genuinely participates, too. In a live retail run, Qwen3 chose `get_order_status` for an order question and `issue_refund_quote` for a refund, filled `order_id` and `reason` from the customer's words, and the confirmation gate held — refund denied until the customer confirmed the *matching* order, then approved:

```
turn1 order   -> model chose get_order_status   (cached_tokens=0)   -> allowed
turn2 refund  -> model chose issue_refund_quote (cached_tokens=256) -> DENIED
turn3 confirm -> model chose issue_refund_quote (cached_tokens=256) -> APPROVED
```

The safety invariants that run in CI (order-id binding, rejecting an unterminated call, the control that "yesterday" is not "yes") are checked against scripted outputs, so they reproduce with no model present. The live model was verified separately. That split is deliberate: the policy properties stay deterministic.

## The custom-op result, in one line each (depth in [Part 4](./04-max-the-platform.md))

- **A Mojo custom op runs in the MAX graph.** `gated_logits` (`@compiler.register`, `def execute`) compiles in and enforces the refund gate as a graph node — and runs inside a live Qwen3's decode loop via `SamplingParams.logits_processors`. Gate closed, the model can't spell the refund tool. *Verified* (`GATE_OP_DEMO_OK`, `LIVE_GATE_OK`).
- **An airtight version rides MAX's own grammar engine.** A `response_format` enum chosen by the policy makes the refund tool structurally unreachable via llguidance. *Verified on H100* (`GRAMMAR_GATE_OK`).

Both are real; the two-gates story is where I unpack what each proves and what it costs.

## What I did NOT measure (the honest column)

A scorecard that only lists wins is marketing. So, plainly:

- **No performance evaluation.** Everything ran on **CPU in float32**; I wrote no GPU kernels and benchmarked none. The custom op runs in the decode loop but I never timed it — on a graph node a vector add is *slower* than host code, and I make no speed claim.
- **Count, not latency.** I measured the *count* of reused tokens (`num_cached_tokens`, and the 1152 warm-start tokens off disk), never the wall-clock or cost that reuse saves, and never compared caching on vs off. There are no tokens-per-second figures because I didn't measure them properly and won't invent them.
- **Durable KV is GPU-only.** The tiered connector offloads device memory and raises on CPU, where the engine falls back to the in-process prefix cache. The warm-start was verified on an H100 with Qwen3-0.6B.
- **The confirmation signal is a coarse keyword check.** The real safety is the order-id binding, not NLP.
- **The live logit-gate was checked on the 0.6B**, which shares the Qwen3 tokenizer with the 8B (identical token ids → identical enforcement) and iterates in seconds.

Read against that column, the result is narrow but solid: a compiled, deterministic, in-process harness with real cache telemetry, byte-exact tool replay, a policy enforced inside the model's decode loop, and a conversation that warm-restarts across processes — all with a model-free CI path behind it. None of it is the drop-in dream [Part 0](./00-curiosity-and-the-plan.md) started from. It's a smaller thing I can stand behind.

---

---

*Previous: [What Ignis Is](./01-what-ignis-is.md). Next: [Mojo, the Language](./03-mojo-the-language.md). [Series index](./ignis.md).*
