---
title: "Part 5 - My Journey, and a Thank-You"
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-ember.svg
sidebar:
  nav: "ignis"
---

*Part 5. The trail told as a trail - the false starts, the crashes, the times MAX was already standing where I thought the frontier was - then the verdict, and a real thank-you to the people building this.*

## How I ended up here

When Chris Lattner is building a language that can be a performant implementation of Python, anyone will take notice. I have been keeping an eye on this development since the announcement.

When Mojo reached 1.0 beta I wanted to measure how far it had come by building something substantial. I had a candidate on disk: an agentic call-center harness in Python - It had all the blocks - ASR, TTS, an LLM, a vector database, the backend glue etc.. I tried porting it to Mojo. The core ported with little friction: the timeline, tool loop, and the policy logic. Everything else was the problem. A call center leans on the parts of Python's gigantic ecosystem - HTTP servers, audio codecs, database drivers etc. and Mojo has none of that yet. The port stalled, and I set it aside.

I came back to it after watching antirez build [`ds4`](https://github.com/antirez/ds4) on a Mac. What caught me was architectural approach: he ran the harness and the model in one runtime, which turns the KV cache from a hidden server detail into state the program can save, reload, and inspect. That made me rethink the whole exercise. Maybe Mojo's job here was smaller than I'd been treating it - the compiled control plane sitting in the same process as the model, with the rest of the call center left to Python. Could Mojo and MAX share a runtime that tightly? That experiment became Ignis.

## The build, in the order it actually happened

The dev log reads as a sequence of "I assumed X; the runtime taught me Y."

**Getting in-process at all** was the first wall, and it was two walls stacked. Driving MAX from a program launched with `mojo run` crashes during model init - `M::Context with different Init::Options` - because the JIT runtime and MAX disagree on the one process-global context. Build the binary and run it, and the context comes up compatibly. Then the obvious entry point, `max.entrypoints.llm.LLM`, fails a second way: it mirrors the serving topology and spawns a worker subprocess, and `spawn` re-execs Python looking for a `__main__` an embedded interpreter doesn't have. The path that works is the lower-level `PIPELINE_REGISTRY.retrieve(...)` + `generate_async(...)`, which runs the model inline - more in-process, and portable to Mojo's embedded interpreter. Both failures live at the seam between Mojo's runtime, an embedded CPython, and MAX's process model. The compiler can't flag them and the docs didn't cover them. You find them by crashing and bisecting.

**Real metrics** came next. The harness during development fabricated cache numbers - `cached_chars = prompt_chars - 160`, fake `checkpoint_saved` / `.kvmeta` events. I wired in MAX's `num_cached_tokens`, which behaves like a real systems number: page-granular, growing `0 → 128 → 256` as the conversation extends, always `<= prompt_tokens`. Logging it unmodified - never rounding up to imply more reuse - became a project rule.

**Letting the model actually choose tools** replaced a keyword-matching version that pre-picked the tool and pinned it. Put the schemas in the request; Qwen3 emits Hermes style `<tool_call>\n{json}\n</tool_call>`; keep the exact bytes; parse with EmberJSON - after learning the hard way that a hand-rolled first-match reader returns the wrong `order_id` when a look-alike key is buried in free text. A tool turn became two calls, with tools and then without, so prefix caching still engages. Along the way, a steady drip of Mojo-1.0 lessons: `fn` is gone, interop moved under `std.python`, `List` isn't implicitly copyable, strings are codepoint-indexed, the EmberJSON serializer won't compile on this build so you re-`parse` instead of re-serialize.

**Then the frontier, and the humbling.** I reached for what felt like Mojo-native edge work, and four times MAX was already there. The agent loop? The cookbook. Enforcing a policy inside generation? `logits_processors`, one file away - I'd assumed it was blocked and was simply wrong; the seam was one grep into the installed source. Fusing a custom op into the sampler? The sampler is already a graph that masks logits. Grammar-constrained decoding? A full conditional tool-call grammar, shipped. I did build a real Mojo custom op (`gated_logits`) and run it inside a live Qwen3's decode loop, which I'm glad I did - it proves compiled Mojo reaches into the model's compute. But the honest move each time was to drive MAX's engine rather than reimplement it. ([Part 4](./04-max-the-platform.md) has the two-gates story in full.)

**The one genuinely non-redundant thing** - or so I thought at the time - was durable session resume. MAX persists KV to disk by token-prefix hash but has no notion of a conversation. Binding the two (persist the timeline, re-render it byte-identically, land on the exact prefix the on-disk KV was keyed on) lets a fresh process warm-start a real conversation: `SESSION_RESUME_OK kv_warmstart_tokens=1152`. Getting there meant working around three `TieredConnector` bugs and discovering that the inviting-looking `use_debug_tiered_mode` silently writes nothing. The load-bearing guarantee is the byte-identical render, so that's the one thing I put under model-free CI; if it ever drifts, the warm-start vanishes silently.

**Two more pushes after I thought I was done.** In-process RAG first. The open question was whether a second MAX pipeline would collide with the first over that same process-global context. It doesn't - `task=PipelineTask.EMBEDDINGS_GENERATION` loads an embedding model beside the LLM, one argument away - and the retrieval index landed on the Mojo side: a SIMD dot-product top-k kernel, the first pure-Mojo compute in the project that's load-bearing rather than a demo. The "one non-redundant thing" turned out to be a whole category: conversation state, then retrieval, the application-side work MAX leaves to you. Then speculative decoding, where build-then-measure earned its keep twice over: three MAX bugs stood between the config flag and a running draft/target pipeline (found by being in-process, patched at the source, filed upstream), and the honest benchmark showed the feature is a net slowdown for this pair - 141.6 tok/s against a 165.7 baseline, about 5.5 ms/cycle of host overhead eating the draft's savings. It ships opt-in, and is switched off by default. Reporting it honestly as a loss in the context of the 8B model that I tested.

(One non-Mojo lesson, recorded because it cost a working tree: review/research sub-agents given write access corrupted the repo more than once. Give them read-only tools.)

## The verdict

For what I built - a compiled, deterministic control plane running in-process with MAX - Mojo at 1.0 beta is ready enough to ship. If your problem is a state machine near a model, Mojo is a credible choice today. For a drop-in replacement of a batteries-included Python application, it isn't, and there's no use pretending: no stdlib JSON, a young service ecosystem, the constant pull toward interop. The ecosystem is three years old.

And the second wall, drawn precisely, because getting its location right is what matters. Ignis shares a runtime with the model in-process, but CPython is still the orchestrator - it loads the model, builds the request, runs the sampling loop. The custom op shows the wall isn't where you'd guess: compiled Mojo *can* reach into the model's compute. What remains is narrower than "Mojo can't touch the model" - it's that the orchestration API is Python, with no Mojo-native way to load Qwen3 and drive `generate`. I will wait for that door to open, but publishing what I could do best today. I'd rather ship the working in-process slice - compiled Mojo in the decode loop, load-bearing Mojo SIMD in the retrieval path - with a clear map of where the wall sits. The repo marks how far the road goes today, with plenty of it still ahead.

---

*Previous: [MAX, the Platform](./04-max-the-platform.md). Back to the start: [The Curiosity and the Plan](./00-curiosity-and-the-plan.md). [Series index](./ignis.md).*
