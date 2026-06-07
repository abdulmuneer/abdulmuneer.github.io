---
title: "Part 3 — Mojo, the Language"
header:
  overlay_image: /assets/images/hero-mojo.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-mojo.svg
sidebar:
  nav: "ignis"
---

*Part 3 of the Ignis expedition. My assessment of Mojo at 1.0 beta, from building a real program in it — not from reading release notes. Where it has matured, where it bites, and the one thing that decides whether it fits your project at all.*

<p><img class="brand-logo" src="/assets/images/brand/mojo-wordmark.svg" alt="Mojo" width="200"></p>

*Mojo and the Mojo flame are trademarks of Modular Inc.; shown here for identification.*



## What Mojo is (and what it isn't)

When Mojo was announced in May 2023, a lot of Python programmers read the pitch the same way I did: a Python-like language with C++-like performance, a superset you could adopt without rewriting anything. A drop-in replacement. It never worked out that way — the distance between code that *looks* like Python and code that *runs* my Python stayed large across every attempt.

The 1.0 beta is a different animal from that 2023 sketch. The right way to understand it is **not** "Python but fast." It's a Python-*family* systems language: static types, value ownership, traits, generics, compile-time parameterization, GPU/kernel authoring — with Python interop as a bridge, not a foundation. Judged as a drop-in Python replacement it loses on ecosystem size. Judged as a compiled control-plane language sitting close to a model runtime, it's a genuinely credible choice today. Ignis is the second test, and that framing matters for everything below.

## New to Mojo? A five-minute primer

*If you already write Mojo, skip to [Why Python is in the loop at all](#why-python-is-in-the-loop-at-all). This section is for getting an absolute newcomer oriented enough to read the rest.*

**Where it comes from.** Mojo is from [Modular](https://www.modular.com/), the company Chris Lattner founded (he created LLVM, Clang, Swift, and MLIR). It's built on **MLIR** and compiles *ahead of time* to native code — so unlike CPython there's no interpreter in the running program. The pitch is one language that spans high-level application logic *and* low-level, GPU-class kernels.

**It looks like Python, but it's statically typed and compiled.** A program has an entry point and prints like you'd expect:

```mojo
def main():
    var name = "world"          # `var` declares a variable
    print("hello,", name)
```

You build it with `mojo build hello.mojo -o hello` and run `./hello`. (There's also `mojo run`, but — see [Part 1](./01-what-ignis-is.md) — anything that brings up MAX must be *built* first.)

**Functions: `def` only.** In the 1.0 beta, `fn` was removed and **`def` is the sole function keyword** — but it now carries strict, typed semantics (the strictness `fn` used to provide). Type annotations are real and checked.

**Structs with value semantics.** You model data as `struct`s, and you opt into copy/move behavior explicitly:

```mojo
struct Order(Copyable, Movable):
    var id: String
    var total: Float64
```

**Ownership is the headline feature.** Every value has one owner; the compiler tracks it. Argument conventions say how a function touches its argument — `read` (borrow, the default), `mut` (mutable borrow), `var`/`out` (it takes ownership) — and `^` *transfers* ownership:

```mojo
def __init__(out self, var outputs: List[String]):
    self.outputs = outputs^      # take ownership of `outputs`, no copy
```

This is why you'll see `.copy()` and `^` dotted through real Mojo: collections like `List` aren't implicitly copyable, so every additional owner is spelled out. It's more typing than Python — and it's what makes the code allocation-honest.

**Traits and generics** are how you write reusable, statically-dispatched code. A `trait` is a compile-time contract; a `struct` satisfies it by implementing its methods; a function can be generic over anything that conforms:

```mojo
trait Greeter:
    def greet(self) -> String: ...

struct Formal(Greeter):
    def greet(self) -> String:
        return "Good day."

def announce[G: Greeter](g: G):   # [G: Greeter] is a compile-time type parameter
    print(g.greet())
```

That `[...]` bracket is **compile-time parameterization** — it can carry types (`[G: Greeter]`) or values (`[n: Int]`), and the compiler specializes a fresh, fast version per instantiation, with no runtime dispatch. This single feature is the spine of Ignis: `process_turn[E: Engine]` is generic over the model backend, so the live model and the no-model test double run the exact same control-plane code.

**Numbers are SIMD-first.** Mojo's scalar types are really vectors of width one (`SIMD[DType.float32, 4]` is four floats in a register), which is what lets the same language express GPU/CPU kernels — the territory of [Part 4](./04-max-the-platform.md)'s custom ops.

**Python is one import away.** When a battery is missing, Mojo embeds CPython and calls it:

```mojo
from std.python import Python

def use_numpy() raises:
    var np = Python.import_module("numpy")
    print(np.array([1, 2, 3]).sum())   # real CPython, in this same process
```

That escape hatch is the entire model path in Ignis — and, as the rest of this part argues, both its superpower and its catch.

**Getting it.** The toolchain ships as the `modular` package (it bundles the `mojo` compiler *and* MAX). Two common ways in: `pixi`/`magic` (Modular's conda-based project manager) or a plain `uv venv` + `uv pip install modular …` from Modular's nightly index. Either gives you `mojo build` and the `max` Python library in one go.

**What the official manual emphasizes.** Modular's own [Mojo manual](https://mojolang.org/docs/manual/) frames the language around writing *high-performance code for CPUs and GPUs*, and it organizes that around a few pillars worth knowing by name:

- **Systems programming** — pointers, explicit memory management, and the value-ownership model above.
- **Metaprogramming** — compile-time evaluation, parameterization, generics, and traits (the `[...]` machinery), so abstractions can cost nothing at runtime.
- **Hardware portability** — one language targeting CPU *and* GPU.
- **Python interoperability** — call Python from Mojo *and* Mojo from Python, so adoption is incremental rather than all-or-nothing.

Note the framing: the docs position Mojo as *complementary to Python through interop*, not as a drop-in superset — which squares exactly with what Ignis ran into below.

That's enough to read on. The rest of this part is what living in it for a real project taught me.

## Why Python is in the loop at all

A fair question lands immediately: if MAX is Modular's Mojo-first runtime and Ignis is Mojo, where does Python enter? It enters **at the API you call.** The kernels, the graph compiler, and on-device execution are compiled, and Mojo is the language they're written in. But the developer-facing surface — load a model, build a request, run `generate` — ships as a Python library, `max.pipelines`. There is no Mojo-native call that loads Qwen3-8B and generates from it. So Ignis takes the only door available and embeds CPython.

The actual path is two Mojo-ish ends with a Python waist:

```
Ignis harness      compiled Mojo        ── ignis.mojo
   │  std.python: embeds a CPython interpreter in THIS process
   ▼
max_engine.py      Python               ── imports max.pipelines, max.driver
   │  tokenizer.delegate = HuggingFace transformers (also Python)
   ▼
PIPELINE_REGISTRY ─► compiled MAX graph + kernels   (native, on-device)
        the model actually executes down here
```

So the headline needs its qualifier. *In-process* is accurate — the model runs in the same OS process as the harness, which is what removes the REST hop. *Pure Mojo* it is not: the path is `Mojo → embedded CPython → MAX's Python API → native kernels`. **Mojo is MAX's kernel language; it is not its orchestration language yet.** Removing CPython entirely would need a Mojo-native inference API that doesn't exist — and that sets the ceiling on how Mojo-native a project like this can be right now.

## Where the language has matured

The 1.0 beta is a real language with a coherent type system, and Ignis leans on the parts that carry weight.

**Traits and generics do real work.** The whole harness is generic over its backend through one trait, so the live model and the test double run the same control-plane code:

```mojo
trait Engine:
    def generate(mut self, messages_json: String, tools_json: String,
                 max_new_tokens: Int) raises -> EngineResult: ...

def process_turn[E: Engine](mut harness: IgnisCore, mut engine: E, ...) raises -> String:
    ...
```

`process_turn[E: Engine]` specializes at compile time — no dynamic dispatch on the hot path — which is exactly what lets `make test` exercise the real logic without a model. The tool boundary uses the same shape (`decode_tool_call[C: ToolCodec]`).

**Structs with value semantics and ownership are clean.** The timeline is an actual `List[SessionEntry]` — a list of structs, not parallel `String` columns dressed up as records. Types declare `Copyable, Movable` explicitly, and the ownership annotations (`mut`, `out`, `var`, and `^` for transfer) make data movement easy to read:

```mojo
def __init__(out self, var outputs: List[String]):
    self.outputs = outputs^      # this backend takes ownership, and says so
```

For deterministic harness code — session state, encoders, parsers, policy checks — this is where Mojo delivers on the systems-language pitch. It already fits.

## Where it bites

Mature is not the same as comfortable, and most of the friction is the ownership model doing its job — which still costs you coming from Python.

- **`List` isn't implicitly copyable.** Every additional owner needs an explicit `.copy()` or a `^` transfer: `var msgs = base_msgs.copy()` where Python would just hand over the reference.
- **Strings are codepoint-indexed**, so string surgery that's casual in Python takes more code. The JSON escaper, `strip_think`, and the FNV-style hash all walk `text.codepoints()` and compare integer code points instead of slicing. Open-ended `s[i:]` fails; you reach for `String.split(...)`. It's the correct Unicode-safe primitive — and it's more typing.
- **Deprecation churn is real.** `fn` is gone (`def` is now the only function keyword), Python interop moved under `std.python`. Sample code from the last two years often won't compile. Mojo is improving *by* churning, and the churn is visible.
- **A dev-build serializer bug cost me real time.** EmberJSON's `to_string` won't compile on this build (`'self' abandoned without being explicitly destroyed`). `parse` and value access are fine, so Ignis works around it by holding the parsed substring and re-`parse`-ing rather than serializing. Nearby cuts: `Object`/`Value` aren't `ImplicitlyCopyable` (borrow with `ref`), and accessors return library types you coerce back with `String(...)` / `Int(...)`.
- **Error messages are serviceable, not a strength.** The failures that cost me most weren't type errors with a clear location — they were cases where the compiler accepted the code and the *runtime* fell over, which diagnostics can't catch.

## Batteries not included — the part that decides fit

This is the wall my original, bigger port hit, and it's what actually decides whether Mojo suits a given project.

**There is no standard-library JSON.** An agent harness is JSON end to end — messages, tool schemas, tool-call payloads, event logs — and the Mojo stdlib parses none of it. Ignis brings in EmberJSON for parsing and hand-writes JSON construction with a manual escaper. The blunt rule I wrote into this codebase — *use EmberJSON, never hand-roll JSON parsing* — is only sensible because the battery is missing.

**The service ecosystem is young.** HTTP servers, async patterns, JSON Schema validation, database drivers, tracing, provider SDKs — none are at Python parity. A call center treats those as the spine, not extras, which is why my full port stalled and Ignis narrowed to a focused harness.

And here's the tension at the heart of the language today: **Python interop is the escape hatch, and leaning on it everywhere quietly gives up the drop-in story.** Mojo can import CPython, so you're never fully blocked — the entire model path in Ignis is `std.python` reaching into MAX. But if every missing battery is answered with "call Python," you haven't replaced Python, you've *wrapped* it. Interop is a migration path and a runtime bridge. It is not a native ecosystem.

## My verdict on the language

For what I built — a compiled, deterministic control plane running in-process with a model — **Mojo at 1.0 beta is ready enough to ship.** Traits, generics, ownership, and structs carried the harness. If your problem is a state machine near a model — a parser, a policy gate, an encoder, a tool loop — Mojo is a credible choice *today*.

For the original goal — a drop-in replacement for a batteries-included Python application — it is not ready, and there's no use pretending otherwise. No stdlib JSON, a young service ecosystem, and the constant pull toward interop the moment you leave the happy path. The ecosystem is three years old; that's the explanation, not a design flaw.

What would help, roughly in the order it cost me: a standard-library JSON module; a serializer that compiles on a stable release; a documented, supported in-process MAX-from-Mojo API (so the integration traps become the platform's problem, not folklore); and a stable channel that doesn't ship dev-build surprises. **None of these are research. They are maturation.** I went back to Mojo to find out whether it had become *Python but fast*. It hasn't — and after Ignis I think that was the wrong test. The framing that fits is the one in [Part 4](./04-max-the-platform.md): a compiled control plane sharing one runtime with the model, where the value is proximity.

---

*Previous: [What Ignis Achieved](./02-what-was-achieved.md). Next: [MAX, the Platform](./04-max-the-platform.md). [Series index](./ignis.md).*
