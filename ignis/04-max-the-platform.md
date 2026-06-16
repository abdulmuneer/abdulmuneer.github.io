---
title: "Part 4 - MAX, the Platform"
header:
  overlay_image: /assets/images/hero-max.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-max.svg
sidebar:
  nav: "ignis"
---

*Part 4, the deep one. What MAX is and where it sits among NVIDIA's stack and the open-source engines; my read on it as an in-process runtime; and the experiment that answers the Mojo question - compiling Ignis's refund policy into the decoder two ways, which is where "is Mojo a peer in the graph or just a wrapper?" gets an answer.*

<p style="text-align:center"><img class="brand-logo" src="/assets/images/brand/max-stack.svg" alt="The MAX stack" style="width:780px;max-width:100%"></p>

*MAX and the MAX stack graphic are trademarks/assets of Modular Inc.; shown here for identification.*



## What MAX is

MAX is unusual in bundling several layers that other vendors ship as separate products. When you say "MAX," you're naming at least four things at once:

1. **A graph compiler** (MLIR-based - Modular was founded by Chris Lattner, who created MLIR) that lowers a model to optimized kernels across hardware.
2. **An LLM serving/pipeline engine** - paged KV cache, prefix caching, continuous batching, the `max.pipelines` API Ignis calls into.
3. **A kernel-authoring language** - Mojo, for custom ops (`@compiler.register` / `ops.custom`).
4. **A portability promise** - the same stack on NVIDIA *and* AMD, deliberately breaking CUDA lock-in.

That bundling is the key to understanding both its competitors and its character.

## New to MAX? A five-minute primer

*If you've already served a model with MAX, skip to [Is there a MAX from NVIDIA?](#is-there-a-max-from-nvidia). This section gets a newcomer oriented.*

**What it's for.** MAX (Modular's inference platform) takes a model - typically a Hugging Face checkpoint like `Qwen/Qwen3-8B` - compiles its computation graph to optimized kernels, and runs or serves it *fast*, on CPU or NVIDIA or AMD GPUs from the same stack. Think "the engine that an LLM endpoint runs on," in the same family as vLLM or TensorRT-LLM, but portable across vendors and with Mojo as its kernel language.

**A few terms, plainly.** A model turns text into **tokens** (sub-word chunks) and generates one token at a time. Each step attends over all previous tokens; to avoid recomputing that, the engine stores per-token key/value vectors in a **KV cache**. **Prefix caching** reuses the KV for a shared prefix across requests - so in a multi-turn chat, the unchanged history isn't re-processed every turn. **Paged attention** is the memory scheme (à la vLLM's PagedAttention) that makes that cache efficient. These aren't trivia: for an agent that re-sends a growing conversation every turn, prefix-cache reuse is most of the performance story, and it's the number [Part 2](./02-what-was-achieved.md) measures.

**The simplest way to use it - serve an OpenAI endpoint.** This is the path Modular leads with and most people start on:

```bash
pip install modular          # or: pixi add max
max serve --model-path Qwen/Qwen3-8B
# now you have an OpenAI-compatible server on localhost:8000:
curl localhost:8000/v1/chat/completions -d '{
  "model": "Qwen/Qwen3-8B",
  "messages": [{"role": "user", "content": "hello"}]
}'
```

Because the API is OpenAI-shaped, your existing client code (the `openai` SDK, LangChain, whatever) points at it unchanged. The model runs in *its own process*; you talk to it over HTTP.

**The way Ignis uses it - in-process Python.** Under the server is a Python library, `max.pipelines`. You can load and drive a model directly, no HTTP, no separate process:

```python
from max.pipelines import PIPELINE_REGISTRY, PipelineConfig
# (the real PipelineConfig is more nested - model path, quantization, device)
tokenizer, pipeline = PIPELINE_REGISTRY.retrieve(PipelineConfig(...))
async for output in pipeline.generate_async(request):
    ...   # output.tokens, and output.num_cached_tokens - the real cache count
```

This is the seam Ignis crosses from Mojo via `std.python`. It's "more in-process" than `max serve` (the model runs inline in the calling thread), which is what lets the harness read MAX's real `num_cached_tokens` and keep the model's exact tool-call bytes without a REST round-trip.

**The deeper layers** are where this part is headed. **MAX Graph** is the symbolic-graph + compiler layer; **Mojo custom ops** (`@compiler.register` / `ops.custom`) let you drop your own compiled kernel into that graph; and the sampler exposes hooks (`SamplingParams.logits_processors`) and production **constrained decoding** (an llguidance grammar engine). Those four are exactly the parts the two gates below are built from - and `Qwen3` here is a "thinking" model, so it emits a `<think>…</think>` preamble the harness strips, a small wrinkle worth knowing before you read live output.

**Mojo, the kernel language.** The orchestration surface above (`max.pipelines`, `max serve`) is Python - but the kernels *under* it are written in Mojo, and custom ops are how you author new ones. That split (Python to drive, Mojo to compute) is the single most important thing to hold onto, and the rest of the series turns on it.

**What the official docs claim (and why it matters here).** Modular describes [MAX](https://docs.modular.com/max/intro/) as a *high-performance AI serving framework* that exposes an OpenAI-compatible endpoint and runs native MAX and PyTorch models across GPUs and CPUs - explicitly **"no CUDA required"** and free of vendor lock-in. Out of the box it advertises:

- an OpenAI-compatible REST API serving **500+ Hugging Face models**;
- graph-compiler optimizations, **quantization**, continuous **batching**, **prefix caching**, and **speculative decoding**;
- **function calling** and **structured output** - the very feature Ignis rides for the airtight grammar gate below;
- **LoRA adapters**, and custom kernels authored in **Mojo**.

You install it with `pip install modular` (the `max` CLI) or run a sub-1 GB Docker container. The thing to notice: nearly every bullet there is a primitive [Part 2](./02-what-was-achieved.md) found *already built* - which is precisely why the harness's job turned out to be **binding** these primitives together; the hard inference work was already built.

## Is there a MAX from NVIDIA?

A colleague, watching me wire Mojo into the in-process pipeline, asked the obvious question: isn't there already an equivalent from NVIDIA, or anyone? The answer depends on *which layer* you mean - no single product covers all four.

**NVIDIA's stack** is the closest single-vendor analog, and philosophically the *opposite* of MAX (deep CUDA lock-in for peak perf, not portability):

| MAX layer | NVIDIA equivalent |
|---|---|
| Graph compiler / engine | **TensorRT** (op fusion, kernel selection, quantization) |
| LLM pipeline (paged KV, in-flight batching, FP8/INT4, spec decode) | **TensorRT-LLM** - the closest analog to `max.pipelines` |
| Serving (`max serve`, OpenAI API) | **Triton Inference Server**¹ + **NIM** (containerized, OpenAI-compatible endpoints) |
| Mojo custom ops | **CUDA C++ / CUTLASS / cuDNN**, or **Triton**¹ (the kernel *language*) |

¹ Two different "Tritons": **Triton Inference Server** (NVIDIA, serving) vs **Triton** (OpenAI, a Python-embedded GPU-kernel DSL). The latter is the nearest cousin to *Mojo as a kernel language* - though Triton is a DSL, not a full systems language.

**The vendor-neutral engines** are arguably MAX's *most direct* functional rivals for what Ignis uses it for - in-process inference with paged/prefix-cached KV:

- **vLLM** - originated **PagedAttention** (the paged-KV idea), continuous batching, prefix caching, OpenAI API; runs on NVIDIA/AMD/Intel. The single closest substitute for MAX's serving layer.
- **SGLang** - **RadixAttention** for prefix caching, strong throughput and structured generation.
- **TGI**, **LMDeploy**, **DeepSpeed-FastGen** - same category. **llama.cpp / GGML** - the lightweight portable end.

**The compiler peers** are MAX's deepest, least-crowded identity: **IREE** (MLIR-based, multi-backend - the closest sibling), **Apache TVM**, **OpenXLA / XLA**. The honest summary:

- the serving engine Ignis calls → **vLLM / SGLang** (and TensorRT-LLM + NIM are NVIDIA's locked-in version);
- the compiler/portability ambition → **IREE / TVM / OpenXLA**;
- Mojo-as-kernel-language inside a portable runtime → **no true peer.** A full systems language that also targets accelerators is Modular's genuinely unusual bet.

There's no "MAX from NVIDIA" because MAX's whole identity is the refusal to be from one vendor - fusing compiler, portable runtime, kernel language, and serving into one stack. Which is exactly why it's the right substrate for an experiment about proximity.

## What MAX gave Ignis

As an in-process runtime, MAX delivered more than I expected, and kept delivering things I'd assumed I would have to build:

- **A genuine in-process path** via `PIPELINE_REGISTRY.retrieve(...)` + `generate_async(...)` - the model runs inline in the calling thread, no worker subprocess.
- **Real cache telemetry** - `num_cached_tokens` per request, page-granular and honest (the subject of [Part 2](./02-what-was-achieved.md)).
- **Custom ops** - compiled Mojo as a node in the model's own graph.
- **A per-request sampler hook** - `SamplingParams.logits_processors`, a callback handed the raw logits each decode step.
- **Production constrained decoding** - llguidance grammar enforcement already wired into the sampler graph.
- **A tiered KV connector** - device→host→disk offload that survives a process restart.
- **More than one pipeline per process** - the same `retrieve(...)` with `task=PipelineTask.EMBEDDINGS_GENERATION` loads an embedding model alongside the LLM, one argument away.
- **Speculative decoding** - a standalone draft/target pipeline behind a config flag.

The middle of that list is what the two gates below are built from. The last two come back at the end.

## Compiling the policy into the decoder

If you want to know whether Mojo is a real participant in the model's computation or just polite host-side glue, make it do something that *has* to happen during token selection. So I took Ignis's signature policy - the order-id-bound refund gate - and tried to move it from host-side control flow into the decoder itself. Can the model be made structurally unable to call `issue_refund_quote` until an exact, matching confirmation opens it?

I built it twice. The gap between the two versions shows exactly where hand-written Mojo stops being enough and you have to fall back on MAX's built-in machinery.

### Gate one - a Mojo custom op, from scratch

The first version (`examples/graph_policy_gate`) is a Mojo custom op compiled into a MAX graph - the smallest real thing, an elementwise additive logit mask:

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

The host computes `mask` from the exact gate (`0.0` to allow, `−1e30` to forbid); applying it in-graph drives the refund token's logit to `−∞`. Two things I braced for and didn't get: it doesn't need `fn` (MAX 26.4's custom-op API is authored with `def`, because in 1.0 beta `def` carries the strict semantics `fn` used to - and stepping *down* to an `fn`-era Mojo would pin an older, incompatible MAX), and the published doc import paths are wrong for this build (the real ones are `extensibility`, `std.gpu.host`, `std.utils.index`; the source of truth is Modular's own `add_constant.mojo`).

It compiles, runs in-process (`GATE_OP_DEMO_OK`, 4/4 turns), and - wired into a live Qwen3's loop through `logits_processors` - runs inside the real sampler each decode step. So yes: a Mojo custom op is a genuine peer in the graph. That half of the question is settled.

But the from-scratch gate is naive token-id suppression, and the model proved it. Forcing the tokenizations of `issue_refund_quote` to `−∞` doesn't block every byte-equivalent path to the same meaning. Closed, the model routed around it:

```
GATE CLOSED (numpy suppressor)      -> tool = issue_request_for_a_quotation
GATE CLOSED (gated_logits Mojo op)  -> tool = issue_deferred_payment
```

An earlier version got beaten by literally `issue_REFUND_QUOTE` - uppercase tokenizes to different ids. You widen the set; the model finds another synonym. It's a losing game for a principled reason: masking token ids can never enumerate every string that *means* the forbidden thing. So the scorecard for gate one: it proves a Mojo op can author, compile, and execute enforcement as a graph node; it's no speedup (routing a vector add through a graph is slower than host code); and it isn't airtight.

### Gate two - riding MAX's own grammar engine

Airtight enforcement is a different mechanism - grammar or FSM-constrained decoding - and gate two (`examples/grammar_policy_gate`) is the admission that I shouldn't write that myself. MAX already ships it: an llguidance bitmask applied inside the sampler graph (`ops.where(bitmask, logits, -inf)`). I reach it through the same in-process pipeline by attaching a `response_format` JSON schema whose tool-name `enum` is the policy:

- gate **closed** → `enum: ["get_order_status"]` → llguidance makes any token path spelling `issue_refund_quote` impossible to produce.
- gate **open** → `enum: ["get_order_status", "issue_refund_quote"]`.

The decision is still Ignis's (the same `is_confirmation` + order-id binding); MAX enforces it, and the forbidden direction is now airtight (`GRAMMAR_GATE_OK`, on an H100). The synonym evasion is structurally gone. It cost a pile of warts I only found by building it: GPU only (`enable_structured_output` raises on CPU); the bare in-process path needs `max_batch_size=1`; greedy (`top_k=1`) required (sampling can pick a padding token above the grammar's vocab range and abort llguidance); enforcement is guaranteed only up to the policy-critical field (the matcher rejects EOS in a non-accepting state and self-disables for the JSON tail - fine for a name-gating policy, but you have to know it); and it emits raw JSON instead of Qwen's Hermes `<tool_call>` wrap, so it doesn't feed the existing `HermesToolCodec`.

### The answer to peer-or-wrapper

Side by side, the two gates turn the question into something more precise than either word:

> Mojo *is* a real peer in the graph for authoring enforcement - a custom op compiles in and runs inside the live sampler, proven. But airtight constrained decoding is a solved problem MAX already owns, and the honest move is to drive that engine instead of reimplementing it.

Mojo is the right tool for small, bespoke decision logic you want compiled next to the model; MAX's grammar engine is the right tool for airtight structural constraints. Neither pure wrapper nor full co-author of the decoder - a peer for the part worth authoring by hand, a disciplined client for the part that isn't.

## The frontier kept being MAX's - except one thing

This is the lesson that kept repeating, and it moves where the real work is. Each time I reached for something that *felt* like the Mojo-native edge, MAX was already standing on it:

1. The agentic loop? The cookbook's `max serve` pattern.
2. Enforcing a policy inside generation? `SamplingParams.logits_processors`, one file away.
3. Fusing a custom op into the sampler? The sampler is already its own graph that masks logits.
4. Grammar-constrained tool decoding? A full conditional tool-call grammar, already shipped.

Four times, a "Mojo frontier" turned out occupied by Python-first MAX. Hand-rolling any of them would have produced a worse copy of something already there. So the open work for a harness like this lies elsewhere - in the part MAX deliberately leaves alone.

There's exactly one such part. MAX's tiered connector persists KV blocks to disk, but it keys them by a hash of the token prefix, not by any session id - by design, the engine has no notion of a conversation, and shouldn't. So the binding is the harness's job: persisting the messages isn't enough, it has to re-render its timeline to byte-identical tokens so the prefix hashes to the same key and the on-disk KV is actually reused. That re-render reproduces the exact token prefix the KV was keyed on, and a fresh process warm-starts on it:

```
SESSION_RESUME_OK kv_warmstart_tokens=1152
```

A separate process, 1152 tokens of the restored conversation served from disk, the model continuing. It rides the regular `TieredConnector` plus a post-generation flush that works around three real connector bugs (an offload off-by-one for single-batch sessions; an async D2H event not ready when `sync()` checks it; metadata not flushed after `wait_for_writes()`). And the whole thing rests on the render staying byte-identical between save and resume - if the system prompt or formatting drifts, the warm-start vanishes silently, with correct output and lost reuse. Which is why that invariant has model-free CI guarding it.

## The pattern, tested twice more

After that writeup I pushed twice more, and both pushes sharpened the lesson rather than overturning it.

**In-process RAG: a second pipeline is a one-argument change.** The open risk was that process-global Modular context - the same one that crashes `mojo run`. Would a *second* pipeline collide with the first? It doesn't. `PIPELINE_REGISTRY.retrieve(config, task=PipelineTask.EMBEDDINGS_GENERATION)` loads an embedding model (mpnet, CPU) beside the Qwen3 LLM (GPU) in one process, verified live on an H100 with both generating. One trap worth its own sentence: MAX's pooled embeddings are not unit vectors (`pool_embeddings=True` mean-pools without L2-normalizing; I saw norms of 42/60/30), so Ignis normalizes at the Python boundary, which makes the Mojo-side dot product cosine similarity. And the division of ownership held exactly as the bet predicted: MAX runs both models; Mojo owns the index and the similarity kernel ([Part 3](./03-mojo-the-language.md) shows it). The "one thing MAX leaves alone" turns out to be a whole category: conversation state was the first member, application-side retrieval is the second.

**Speculative decoding: advertised, shipped, and at this scale a measured loss.** The feature list above advertises it, and it's really there: a standalone draft/target mode where Qwen3-0.6B proposes *k* tokens and Qwen3-8B verifies them in one pass. But the path was unwalked enough that three bugs stood between `retrieve()` and a running pipeline: a `Dim + TensorValue` type error in the target's logits graph (already fixed upstream; backported), the draft model being built from the *target's* config (an 8B graph loading 0.6B weights), and the draft's second step arriving one graph input short (a dropped `draft_attention_dispatch_metadata`). All three are patched in-harness and filed in `docs/upstream-findings.md`. Then the honest benchmark - one H100, greedy, three 256-token runs after warm-up: baseline **165.7 tok/s**, spec k=2 **141.6 tok/s**. The arithmetic explains it: a k=2 cycle should cost about 9.7 ms of compute but measures about 15.2 ms - roughly 5.5 ms/cycle of host-side overhead in MAX's spec pipeline - and break-even at k=2 needs about 2.4 accepted tokens per cycle where the real pair delivers 2.15. The synthetic-acceptance ceiling (1.8× at k=5) says the machinery wins where target steps dwarf the fixed overhead - on bigger, slower targets than 8B. So it ships opt-in behind `IGNIS_DRAFT_MODEL`, off by default, with `scripts/bench_speculative.py` for pairs where the math changes.

Two refinements to the lesson, then. The parts MAX leaves alone are the application-side state and compute - conversations, retrieval indexes - and that's where harness Mojo earns its keep. And "already shipped" doesn't mean "already walked": being in-process is what turned three upstream bugs from blockers into findings, and being metric-honest is what turned a speedup feature into a correctly-reported slowdown.

## My verdict on MAX

As an in-process runtime, MAX is further along than its Python-first positioning suggests, and that's the headline: compiled Mojo can already reach into the model's compute today - a custom op runs as a node in the graph, on the live logits, in the decode loop. The obstacle was never that two compiled worlds can't meet. What remains is narrower and specific: the orchestration API is Python. There's no Mojo-native way to load Qwen3 and drive `generate`, so the loop runs from CPython even while a Mojo kernel works inside it. A documented, supported in-process MAX-from-Mojo API would remove the integration traps and the last layer of CPython at once.

The other thing to credit honestly: MAX's instinct to ship the hard inference primitives (paged KV, prefix caching, logits hooks, llguidance grammar, tiered offload, multi-pipeline processes, speculative decoding) means a harness author should reach for them first - measuring before believing - and reserve Mojo for the bespoke edges and the application-level state and compute MAX leaves open: conversations, retrieval indexes, the similarity kernel. I don't read any of that as a shortcoming in MAX. It's the right division of labor, and finding it was half the value of the expedition.

---

*Previous: [Mojo, the Language](./03-mojo-the-language.md). Next: [My Journey](./05-the-journey.md). [Series index](./ignis.md).*
