---
title: "Part 4 — MAX, the Platform"
nav_order: 5
---

# Ignis — Finding Your Mojo from DwarfStar

## Part 4 — MAX, the Platform

*Part 4 of the Ignis expedition. The deep one. What MAX is and where it sits among NVIDIA's stack and the open-source engines; my assessment of it as an in-process runtime; and the technical climax — compiling Ignis's refund policy into the decoder two ways, which is where "is Mojo a peer in the graph or just a wrapper?" finally gets answered.*

---

### What MAX is

MAX is unusual in bundling several layers that other vendors ship as separate products. When you say "MAX," you're naming at least four things at once:

1. **A graph compiler** (MLIR-based — Modular was founded by Chris Lattner, who created MLIR) that lowers a model to optimized kernels across hardware.
2. **An LLM serving/pipeline engine** — paged KV cache, prefix caching, continuous batching, the `max.pipelines` API Ignis calls into.
3. **A kernel-authoring language** — Mojo, for custom ops (`@compiler.register` / `ops.custom`).
4. **A portability promise** — the same stack on NVIDIA *and* AMD, deliberately breaking CUDA lock-in.

That bundling is the key to understanding both its competitors and its character.

### Is there a MAX from NVIDIA?

A colleague, watching me wire Mojo into the in-process pipeline, asked the obvious question: isn't there already an equivalent from NVIDIA, or anyone? The answer depends on *which layer* you mean — no single product covers all four.

**NVIDIA's stack** is the closest single-vendor analog, and philosophically the *opposite* of MAX (deep CUDA lock-in for peak perf, not portability):

| MAX layer | NVIDIA equivalent |
|---|---|
| Graph compiler / engine | **TensorRT** (op fusion, kernel selection, quantization) |
| LLM pipeline (paged KV, in-flight batching, FP8/INT4, spec decode) | **TensorRT-LLM** — the closest analog to `max.pipelines` |
| Serving (`max serve`, OpenAI API) | **Triton Inference Server**¹ + **NIM** (containerized, OpenAI-compatible endpoints) |
| Mojo custom ops | **CUDA C++ / CUTLASS / cuDNN**, or **Triton**¹ (the kernel *language*) |

¹ Two different "Tritons": **Triton Inference Server** (NVIDIA, serving) vs **Triton** (OpenAI, a Python-embedded GPU-kernel DSL). The latter is the nearest cousin to *Mojo as a kernel language* — though Triton is a DSL, not a full systems language.

**The vendor-neutral engines** are arguably MAX's *most direct* functional rivals for what Ignis uses it for — in-process inference with paged/prefix-cached KV:

- **vLLM** — originated **PagedAttention** (the paged-KV idea), continuous batching, prefix caching, OpenAI API; runs on NVIDIA/AMD/Intel. The single closest substitute for MAX's serving layer.
- **SGLang** — **RadixAttention** for prefix caching, strong throughput and structured generation.
- **TGI**, **LMDeploy**, **DeepSpeed-FastGen** — same category. **llama.cpp / GGML** — the lightweight portable end.

**The compiler peers** are MAX's deepest, least-crowded identity: **IREE** (MLIR-based, multi-backend — the closest sibling), **Apache TVM**, **OpenXLA / XLA**. The honest summary:

- the serving engine Ignis calls → **vLLM / SGLang** (and TensorRT-LLM + NIM are NVIDIA's locked-in version);
- the compiler/portability ambition → **IREE / TVM / OpenXLA**;
- Mojo-as-kernel-language inside a portable runtime → **no true peer.** A full systems language that also targets accelerators is Modular's genuinely unusual bet.

There's no "MAX from NVIDIA" because MAX's whole identity is the *refusal* to be from one vendor — fusing compiler, portable runtime, kernel language, and serving into one stack. Which is exactly why it's the right substrate for an experiment about *proximity*.

### What MAX gave Ignis

As an in-process runtime, MAX delivered more than I expected, and kept delivering things I assumed I'd have to build:

- **A genuine in-process path** via `PIPELINE_REGISTRY.retrieve(...)` + `generate_async(...)` — the model runs inline in the calling thread, no worker subprocess.
- **Real cache telemetry** — `num_cached_tokens` per request, page-granular and honest (the subject of [Part 2](./02-what-was-achieved.md)).
- **Custom ops** — compiled Mojo as a node in the model's own graph.
- **A per-request sampler hook** — `SamplingParams.logits_processors`, a callback handed the raw logits each decode step.
- **Production constrained decoding** — llguidance grammar enforcement already wired into the sampler graph.
- **A tiered KV connector** — device→host→disk offload that survives a process restart.

The last four are the ingredients for the technical climax, and for a lesson that kept repeating.

### The climax: compiling a policy into the decoder

If you want to know whether Mojo is a real participant in the model's computation or just polite host-side glue, make it do something that *has* to happen during token selection. So I took Ignis's signature policy — the order-id-bound refund gate — and tried to move it from host-side control flow *into the decoder itself*: can the model be made **structurally unable** to call `issue_refund_quote` until an exact, matching confirmation opens it?

I built it twice, and the gap between the two versions is the actual shape of today's frontier.

#### Gate one — a Mojo custom op, from scratch

The first version (`examples/graph_policy_gate`) is a Mojo custom op compiled into a MAX graph — the smallest real thing, an elementwise additive logit mask:

```mojo
@compiler.register("gated_logits")
struct GatedLogits:
    @staticmethod
    def execute[target: StaticString](
        output: OutputTensor,
        logits: InputTensor[dtype = output.dtype, rank = output.rank, ...],
        mask:   InputTensor[dtype = output.dtype, rank = output.rank, ...],
        ctx: DeviceContext,
    ) raises:
        # the whole policy enforcement, as a graph node: out[i] = logits[i] + mask[i]
```

The host computes `mask` from the exact gate (`0.0` to allow, `−1e30` to forbid); applying it in-graph drives the refund token's logit to `−∞`. Two things I braced for and didn't get: it **doesn't need `fn`** (MAX 26.4's custom-op API is authored with `def`, because in 1.0 beta `def` carries the strict semantics `fn` used to — and stepping *down* to an `fn`-era Mojo would pin an older, incompatible MAX), and the **published doc import paths are wrong** for this build (the real ones are `extensibility`, `std.gpu.host`, `std.utils.index`; the source of truth is Modular's own `add_constant.mojo`).

It compiles, runs in-process (`GATE_OP_DEMO_OK`, 4/4 turns), and — wired into a live Qwen3's loop through `logits_processors` — runs *inside the real sampler each decode step*. **Yes, a Mojo custom op is a genuine peer in the graph.** That half of the question is settled and verified.

But the from-scratch gate is **naive token-id suppression**, and the model proved it. Forcing the tokenizations of `issue_refund_quote` to `−∞` doesn't block every byte-equivalent path to the same meaning. Closed, the model routed around it:

```
GATE CLOSED (numpy suppressor)      -> tool = issue_request_for_a_quotation
GATE CLOSED (gated_logits Mojo op)  -> tool = issue_deferred_payment
```

An earlier version got beaten by literally `issue_REFUND_QUOTE` — uppercase tokenizes to different ids. You widen the set; the model finds another synonym. It's a losing game for a principled reason: masking token ids can never enumerate every string that *means* the forbidden thing. So the honest scorecard for gate one: ✅ proves a Mojo op can author + compile + execute enforcement as a graph node; ❌ no speedup (routing a vector add through a graph is *slower*); ❌ not airtight.

#### Gate two — riding MAX's own grammar engine

Airtight enforcement isn't token masking, it's grammar/FSM-constrained decoding — and the second gate (`examples/grammar_policy_gate`) is the admission that *I shouldn't write that myself.* MAX already ships it: an llguidance bitmask applied inside the sampler graph (`ops.where(bitmask, logits, -inf)`). I reach it through the same in-process pipeline by attaching a `response_format` JSON schema whose tool-name `enum` **is** the policy:

- gate **closed** → `enum: ["get_order_status"]` → llguidance makes any token path spelling `issue_refund_quote` *impossible*. Not improbable — impossible.
- gate **open** → `enum: ["get_order_status", "issue_refund_quote"]`.

The decision is still Ignis's (the same `is_confirmation` + order-id binding); MAX *enforces* it, and the forbidden direction is now airtight (`GRAMMAR_GATE_OK`, on an H100). The synonym evasion is structurally gone. It cost a pile of warts I only found by building it: **GPU only** (`enable_structured_output` raises on CPU); the bare in-process path needs **`max_batch_size=1`**; **greedy (`top_k=1`) required** (sampling can pick a padding token above the grammar's vocab range and abort llguidance); enforcement is **guaranteed only up to the policy-critical field** (the matcher rejects EOS in a non-accepting state and self-disables for the JSON tail — fine for a name-gating policy, but you have to know it); and it's a **parallel raw-JSON path**, not Qwen's Hermes `<tool_call>` wrap, so it doesn't feed the existing `HermesToolCodec`.

#### The answer to peer-or-wrapper

Side by side, the two gates resolve the question into something more precise than either word:

> Mojo **is** a real peer in the graph for *authoring* enforcement — a custom op compiles in and runs inside the live sampler, proven. But *airtight* constrained decoding is a solved problem MAX already owns, and the honest move is to drive that engine, not reimplement it.

Mojo is the right tool for *small, bespoke* decision logic you want compiled next to the model; MAX's grammar engine is the right tool for airtight structural constraints. Neither pure wrapper nor full co-author of the decoder — a peer for the part worth authoring by hand, a disciplined client for the part that isn't.

### The frontier kept being MAX's — except one thing

This is the lesson that kept repeating, and it relocates where the real work is. Each time I reached for something that *felt* like the Mojo-native edge, MAX was already standing on it:

1. The agentic loop? The cookbook's `max serve` pattern.
2. Enforcing a policy inside generation? `SamplingParams.logits_processors`, one file away.
3. Fusing a custom op into the sampler? The sampler is already its own graph that masks logits.
4. Grammar-constrained tool decoding? A full conditional tool-call grammar, already shipped.

Four times, a "Mojo frontier" turned out occupied by Python-first MAX. Hand-rolling any of them would have been a worse copy of something already there. **The open work for a harness like this is not reimplementing inference primitives in Mojo. It's the part MAX deliberately leaves alone.**

There is exactly one such part. MAX's tiered connector persists KV blocks to disk keyed by token-prefix hash — but MAX has **no concept of a conversation**: it won't store your message history, and it doesn't know a fresh process is the same session as a dead one. So I built that binding. The harness persists its timeline and restores it so the re-rendered prompt is *byte-identical*, reproducing the exact token prefix the on-disk KV was keyed on:

```
SESSION_RESUME_OK kv_warmstart_tokens=1152
```

A separate process, 1152 tokens of the restored conversation served from disk, the model continuing — resume, not replay. It rides the *regular* `TieredConnector` plus a post-generation flush that works around three real connector bugs (an offload off-by-one for single-batch sessions; an async D2H event not ready when `sync()` checks it; metadata not flushed after `wait_for_writes()`). And the whole thing rests on the render staying byte-identical between save and resume — if the system prompt or formatting drifts, the warm-start vanishes silently, with correct output and lost reuse. Which is why that invariant has model-free CI guarding it.

### My verdict on MAX

As an in-process runtime, MAX is further along than its Python-first positioning suggests, and that's the headline: **compiled Mojo can already reach into the model's compute today** — a custom op runs as a node in the graph, on the live logits, in the decode loop. The obstacle was never that two compiled worlds can't meet. What remains is narrower and specific: **the orchestration API is Python.** There's no Mojo-native way to load Qwen3 and drive `generate`, so the loop runs from CPython even while a Mojo kernel works inside it. A documented, supported in-process MAX-from-Mojo API would remove the integration traps and the last layer of CPython at once.

The other thing to credit honestly: MAX's instinct to ship the hard inference primitives (paged KV, prefix caching, logits hooks, llguidance grammar, tiered offload) means a harness author should *reach for them first* and reserve Mojo for the bespoke edges and the conversation-level state MAX leaves open. That's not a limitation of MAX — it's the correct division of labor, and finding it was half the value of the expedition.

---

---

*Previous: [Mojo, the Language](./03-mojo-the-language.md). Next: [My Journey](./05-the-journey.md). [Series index](./index.md).*
