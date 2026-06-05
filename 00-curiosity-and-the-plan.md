---
title: "Part 0 — The Curiosity and the Plan"
nav_order: 1
---

# Ignis — Finding Your Mojo from DwarfStar

## Part 0 — The Curiosity and the Plan

*Part 0 of the Ignis expedition. Before the code, the why: what made me curious about Mojo and MAX, why I decided to build instead of read, and the plan I set out with. The later posts are field notes; this is the trailhead.*

---

### The itch

I keep a short list of technologies I trust enough to be skeptical about — things I've read the pitch for, nodded at, and never actually put my hands inside. Mojo and MAX had been on that list for a while. The pitch is easy to admire from a distance: a Python-family systems language with real ownership and compile-time machinery, sitting on top of an MLIR-based model runtime that compiles graphs and serves models across hardware. Easy to admire, and easy to never verify.

What I wanted wasn't another summary of the release notes. I wanted the innards. How does Mojo's ownership model actually feel when you're threading a parser through it? What does MAX's prefix cache *really* report, versus what a blog post claims it reports? Where does the "Python superset" story hold and where does it quietly break? You don't learn that by reading. You learn it by building something demanding enough that the abstractions have to either hold or crack in your hands.

So the motivation for this whole expedition is plain: **build a real thing on Mojo and MAX, and write down what the stack actually does — not what it's marketed to do.**

### The spark

The shape of the thing came from watching antirez build [`ds4`](https://github.com/antirez/ds4), his small DeepSeek runtime. The part that grabbed me wasn't the kernels. It was an architectural decision: he ran the harness and the model **in one runtime**. That single choice turns the KV cache from a hidden detail of some inference server into *state your program owns* — something you can save, reload, and inspect. The session stops being a stateless request to a black box and becomes a first-class object the agent loop holds onto.

Once you see that, the usual setup looks backwards. The standard path is `max serve` in one process, a FastAPI app in another, talking OpenAI-compatible JSON over HTTP. Clean, scalable, and completely opaque about the thing I actually wanted to study. The leverage is in owning the loop. So the question that became this project was narrow and specific:

> Can a compiled Mojo control plane and a MAX-served model share a single OS process tightly enough to make inference state — KV cache, tool bytes, policy, events — something the harness owns rather than something it asks a server for?

That question is the whole expedition. Everything else is detail.

### The bet

The bet I'm making, and the one this series tests, is a division of ownership:

- **Mojo owns the deterministic control plane** — the session timeline, prompt rendering, tool parsing, the policy gate, the append-only event log, replay bytes, telemetry. The parts that benefit from being compiled, ownership-checked, and free of dynamic Python in the hot path.
- **MAX owns model execution** — graph compilation, the model kernels, the prefix/KV cache, generated text.

And one honesty clause I'm committing to up front, because it's the easiest thing to get wrong in the marketing direction: **"shared runtime" means in-process, not pure Mojo.** The real path is `Mojo → embedded CPython → MAX's Python pipeline → native kernels`. MAX has deprecated its Mojo-language inference APIs in favor of Python; Mojo's reserved frontier is GPU-kernel and custom-op authoring. I'd rather state that plainly at the trailhead than discover halfway up that I've been selling a "Mojo-to-MAX direct" story that isn't true. The genuinely Mojo-native frontier runs the *other* way — compiling agent decisions *into* the MAX graph as custom ops — and that's the long game, not a workaround.

There's a second clause, just as important: **no fabricated metrics.** If I report a cache number, it's MAX's real `num_cached_tokens`, page-granular and as-measured. The temptation in a project like this is to dress up the telemetry. The point of the expedition is the opposite — to find out what's actually there.

### The plan

I'm not trying to clone `ds4`. The serious translation is architectural, not line-by-line, and it staged out as a roadmap:

- **M0 — control plane.** A Mojo harness with a typed session timeline, tool parsing, and a policy gate, runnable with *no model at all* via a deterministic fixture backend. (The trick that makes the whole thing testable: one `Engine` trait, two implementations — real and fixture — behind a single generic turn loop. CI exercises the entire harness without a GPU.)
- **M1 — a real repo.** Makefile, docs, fixtures, CI that's green without a model.
- **M2 — real MAX.** One supported model, one tool-capable template, real prefix-cache reuse measured per turn. *(This is where the in-process bet gets proven or doesn't.)*
- **M3 — the `ds4` lesson, head-on.** Store the exact rendered prompt bytes and the exact model-emitted tool-call bytes; replay them; build a cache-identity report every turn.
- **M4 — Mojo/MAX synergy.** Push agent decisions into the MAX graph: an intent router, a refund-risk scorer, a small verifier — as Mojo custom ops sharing the model's graph.
- **M5 — deeper integration.** Durable KV checkpoints across processes, custom-architecture experiments — wherever the public APIs let me reach.

The center of gravity, deliberately, is **M2–M3**: get the model in-process, prove the cache is real, and make the session something the harness owns. M4 is the part I'm most curious about and least sure of — it's where "is Mojo actually a peer here, or just a wrapper?" gets answered.

### What this series is

These posts are the log of going up that trail: what compiled, what crashed, what the docs promised versus what the runtime delivered, and where the Mojo-native dream stops at today's APIs. I'm releasing it whether or not it reaches the summit — a stack's real shape shows as clearly in where it stops you as in where it lets you through.

If you want the verdict before the journey, it's [Part 5](./05-the-journey.md) — but the parts between are where it's earned.

---

*Next: What Ignis Is — the artifact, and how to run it. [Series index](./index.md).*

---

---

*Next: [What Ignis Is](./01-what-ignis-is.md). [Series index](./index.md).*
