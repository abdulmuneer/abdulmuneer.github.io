---
title: "Part 5 — My Journey, and a Thank-You"
nav_order: 6
---

# Ignis — Finding Your Mojo from DwarfStar

## Part 5 — My Journey, and a Thank-You

*Part 5 of the Ignis expedition. The trail told as a trail — the false starts, the crashes, the four times MAX was already standing where I thought the frontier was — and then the verdict, and a genuine appreciation for what Modular has built.*

---

### How I ended up here

When Mojo was announced in May 2023, I read the pitch the way a lot of Python programmers did: a Python-like language with C++-like performance, a superset I could adopt without rewriting anything. I wanted a drop-in replacement. It never worked out that way — the distance between code that *looks* like Python and code that *runs* my Python stayed large.

When Mojo reached 1.0 beta I wanted to measure how far it had come by *building* something substantial instead of reading release notes. I had a candidate on disk: an agentic call-center harness in Python — ASR, TTS, an LLM, a vector database, the backend glue. The core ported with little friction — the timeline, the tool loop, the policy logic. Everything else was the problem. A call center leans on the parts of Python you stop noticing: HTTP servers, audio codecs, database drivers, the JSON that's simply *present* in any Python project. Mojo has none of that yet. The port stalled, and I set it aside.

I came back after watching antirez build [`ds4`](https://github.com/antirez/ds4) on a Mac. What caught me wasn't the kernels — it was architectural: he ran the harness and the model in **one runtime**, which turns the KV cache from a hidden server detail into state the program can save, reload, and inspect. It reframed the port. Maybe Mojo's job here wasn't to replace Python across the whole call center, but to be the compiled control plane sitting in the same process as the model. Could Mojo and MAX share a runtime that tightly? That experiment became Ignis.

### The build, in the order it actually happened

The dev log reads as a sequence of "I assumed X; the runtime taught me Y."

**Getting in-process at all** was the first wall, and it was two walls stacked. Driving MAX from a program launched with `mojo run` crashes during model init — `M::Context with different Init::Options` — because the JIT runtime and MAX disagree on the one process-global context. *Build* the binary and run it, and the context comes up compatibly. Then the obvious entry point, `max.entrypoints.llm.LLM`, fails a second way: it mirrors the serving topology and spawns a worker subprocess, and `spawn` re-execs Python looking for a `__main__` an embedded interpreter doesn't have. The path that works is the lower-level `PIPELINE_REGISTRY.retrieve(...)` + `generate_async(...)`, which runs the model inline — *more* in-process, and portable to Mojo's embedded interpreter. Both failures live at the seam between Mojo's runtime, an embedded CPython, and MAX's process model; the compiler can't flag them and the docs didn't cover them. You find them by crashing and bisecting.

**Real metrics** came next. The harness I inherited *fabricated* cache numbers — `cached_chars = prompt_chars - 160`, fake `checkpoint_saved`/`.kvmeta` events. I tore that out and wired in MAX's genuine `num_cached_tokens`, which behaves like a real systems number: page-granular, growing `0 → 128 → 256` as the conversation extends, always `<= prompt_tokens`. Logging it *unmodified* — never rounding up to imply more reuse — became a project principle.

**Letting the model actually choose tools** replaced a keyword-matching impostor that pre-picked the tool and pinned it. Put the schemas in the request; Qwen3 emits Hermes `<tool_call>{json}</tool_call>`; keep the exact bytes; parse with **EmberJSON** (after learning the hard way that a hand-rolled first-match reader returns the wrong `order_id` when a look-alike key is buried in free text). A tool turn became two calls — with tools, then without — so prefix caching still engages. Along the way, a steady drip of Mojo-1.0 lessons: `fn` is gone, interop moved under `std.python`, `List` isn't implicitly copyable, strings are codepoint-indexed, the EmberJSON serializer won't compile on this build so you re-`parse` instead of re-serialize.

**Then the frontier — and the humbling.** I reached for what felt like Mojo-native edge work, and *four times* MAX was already there. The agent loop? The cookbook. Enforcing a policy inside generation? `logits_processors`, one file away — I had assumed it was blocked and was simply wrong; the seam was one grep into the installed source. Fusing a custom op into the sampler? The sampler's already a graph that masks logits. Grammar-constrained decoding? A full conditional tool-call grammar, shipped. I did build a real Mojo custom op (`gated_logits`) and run it *inside* a live Qwen3's decode loop, which I'm glad I did — it proves compiled Mojo reaches into the model's compute. But the honest move each time was to *drive* MAX's engine, not reimplement it. ([Part 4](./04-max-the-platform.md) has the two-gates story in full.)

**The one genuinely non-redundant thing** I found last: durable session resume. MAX persists KV to disk by token-prefix hash but has no notion of a *conversation*. Binding the two — persist the timeline, re-render it byte-identically, land on the exact prefix the on-disk KV was keyed on — let a fresh process warm-start a real conversation: `SESSION_RESUME_OK kv_warmstart_tokens=1152`. Getting there meant working around three `TieredConnector` bugs and discovering that the inviting-looking `use_debug_tiered_mode` silently writes nothing. The load-bearing guarantee — the byte-identical render — is the one thing I put under model-free CI, because if it ever drifts the warm-start vanishes silently.

(One non-Mojo lesson, recorded because it cost a working tree: review/research sub-agents given write access corrupted the repo more than once. Give them read-only tools.)

### The verdict

For what I built — a compiled, deterministic control plane running in-process with MAX — **Mojo at 1.0 beta is ready enough to ship.** If your problem is a state machine near a model, Mojo is a credible choice today. For a drop-in replacement of a batteries-included Python application, it is not, and there's no use pretending: no stdlib JSON, a young service ecosystem, the constant pull toward interop. The ecosystem is three years old; that's the explanation, not a design flaw.

And the second wall, drawn precisely, because getting its *location* right is the whole point. Ignis shares a runtime with the model in-process, but CPython is still the orchestrator — it loads the model, builds the request, runs the sampling loop. The custom op shows the wall isn't where you'd guess: compiled Mojo *can* reach into the model's compute. What remains is narrower than "Mojo can't touch the model" — it's that the *orchestration* API is Python, with no Mojo-native way to load Qwen3 and drive `generate`. I could have waited for that door to open before publishing. I'd rather ship the working in-process slice, with compiled Mojo in the decode loop, plus a clear map of where the wall sits. **The repo marks how far the road goes, not where it ends.**

### A thank-you to Modular

It would be easy to read five parts of "here's where it bit me" as a complaint. It isn't one. Every sharp edge in this series exists because Modular is attempting something genuinely hard and genuinely worth doing: a single language that spans agent logic, systems code, and graph-compiled kernels, on a runtime that refuses to be locked to one vendor's silicon. Most of the ambition has *landed*. Mojo's ownership model, traits, and generics carried a real harness cleanly. MAX's in-process pipeline, honest cache telemetry, custom ops, the logits-processor seam, the llguidance grammar engine, and the tiered KV connector are not toys — they're the load-bearing primitives that made every result here possible, and most of them were already there when I went looking. The recurring experience of reaching for the frontier and finding Modular already standing on it is, in the end, a compliment to how much they've built.

The things I'd ask for — stdlib JSON, a serializer that compiles on a stable channel, a documented in-process MAX-from-Mojo API, a release channel without dev-build surprises — are maturation, not research. They're the predictable asks of someone who pushed a three-year-old ecosystem hard enough to find its current edges, which is exactly what I set out to do. To the people building Mojo and MAX: thank you. You've made something I could build a real thing on, learn a great deal from, and stand behind — and you've drawn the frontier close enough that an outsider with a side project can reach it in a few weeks. That's rare, and it's the reason this expedition was worth taking.

---

*Previous: [MAX, the Platform](./04-max-the-platform.md). Back to the start: [The Curiosity and the Plan](./00-curiosity-and-the-plan.md). [Series index](./index.md).*
