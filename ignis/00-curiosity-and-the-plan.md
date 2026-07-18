---
title: "Part 0 - The Curiosity and the Plan"
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-ember.svg
sidebar:
  nav: "ignis"
---

*Part 0 of the series. Before any code, the why: what got me curious about Mojo and MAX, why I built instead of read, and the plan I started with.*

<p style="text-align:center"><img class="brand-logo" src="/assets/images/roadmap.svg" alt="The M0 to M5 plan" style="width:720px;max-width:100%"></p>



## The itch

As a career-long pythonista, Mojo and MAX had been on my list of `technologies to look out for` for a couple of years. The pitch is easy to like from a distance: a Python-family systems language with real ownership and compile-time machinery, sitting on an MLIR-based runtime that compiles models and serves them across hardware. I did some previous tests with Mojo to find out if it could replace Python, and soon relaized that was not the case. Then I noticed this almost parallel development and promotion of Max platform. So when Modular announced the 1.0beta of Mojo, I thought it was time for another round experiments.


So the plan was to build a real thing on Mojo and MAX, and understand what the stack does through that journey. Build something big enough that the abstractions have to either hold or break in your hands.

## The spark

The shape of the thing came from watching antirez build [`ds4`](https://github.com/antirez/ds4), that started as a DeepSeek runtime and evolved. Beyond the kernels, what stuck with me was that he ran the harness and the model in one runtime. Now the KV cache becomes a state your program owns - something you can save, reload, and look at. The session turns into an object the agent loop holds, instead of a request it fires at a black box.

Once you've seen it that way, the usual setup looks backwards: `max serve` in one process, a FastAPI app in another, OpenAI-shaped JSON over HTTP between them. Clean and scalable, and completely opaque about the one thing I wanted to study. So the question I ended up with was narrow:

> Can a compiled Mojo control plane and a MAX-served model share a single OS process tightly enough that inference state - KV cache, tool bytes, policy, events - is something the harness owns rather than something it asks a server for?

That's the experiment that I call Ignis :) .

## The bet

The bet is a split of ownership:

- **Mojo owns the typed control plane** - the session timeline, prompt rendering,
  tool parsing, policy, event log, and telemetry. It does not need to replace
  mature storage or service libraries to own that boundary. Filesystems,
  databases, and local HTTP remain suitable Python responsibilities when they
  are not the compute being optimized.
- **MAX owns model execution** - graph compilation, the kernels, the KV cache, generated text.

One thing I want to be straight about up front, because it's the easy claim to oversell: "shared runtime" means in-process, not pure Mojo. The real path is `Mojo → embedded CPython → MAX's Python pipeline → native kernels`. MAX deprecated its Mojo-language inference APIs in favour of Python, and the frontier it keeps for Mojo is GPU kernels and custom ops. I'd rather say that here than have you find out three parts in that I've been quietly selling "Mojo-to-MAX, direct." The actually-Mojo-native direction runs the other way - pushing agent decisions *into* the graph as custom ops - and that's a longer game than one side project.


## The plan

I looked at `ds4` and tried to translate the architecture, not the code - and the runtime gap is worth naming up front, because the whole series lives inside it. ds4 is a self-contained C engine: its own CUDA and Metal kernels, the agent loop and the inference loop the same program, with direct reach into the KV cache and the logits. Ignis can't be that - it drives MAX's Python pipeline across a CPython boundary - so it reaches for the same *property*, the session as KV state the program owns, by assembling MAX's primitives in one process rather than by owning the engine. It became apparent over a few iterations that MAX was already standing on every hill I'd set out to conquer, so a drop-in ds4 equivalent was never on the table. I staged out a rough roadmap instead:

- **M0 - control plane.** A Mojo harness with a typed timeline, tool parsing, and a policy gate that runs with no model at all, through a fixture backend. One `Engine` trait, two implementations, one generic turn loop - so CI can exercise the whole harness without a GPU.
- **M1 - a real repo.** Makefile, docs, fixtures, model-free CI.
- **M2 - real MAX.** One supported model, one tool-capable template, real prefix-cache reuse measured per turn. This is where the in-process bet gets proven or doesn't.
- **M3 - the `ds4` lesson.** Store the exact prompt bytes and the exact tool-call bytes, replay them, build a real cache report every turn.
- **M4 - Mojo in the graph.** Push an agent decision into the MAX graph as a Mojo custom op.
- **M5 - deeper integration.** Durable KV across processes, and whatever else the public APIs let me reach.

The weight is on M2–M3: get the model in-process, prove the cache is real, make the session something the harness owns. M4 was the part I was least sure of going in. It's where "is Mojo a peer in this graph, or just a wrapper around it?" gets a real answer.

## What this series is

A log of going up that trail. What compiled, what crashed, where the docs and the runtime disagreed, and where the Mojo-native idea runs into the APIs that exist today. I'm publishing it whether or not it reached the top, because a stack shows its shape as much in where it stops you as in where it lets you through.

If you want the verdict before the journey, it's in [Part 5](./05-the-journey.md). The parts in between are where it's earned.

---

*Next: [What Ignis Is](./01-what-ignis-is.md). [Series index](./ignis.md).*
