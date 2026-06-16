---
title: "Part 3 - Mojo, the Language"
header:
  overlay_image: /assets/images/hero-mojo.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-mojo.svg
sidebar:
  nav: "ignis"
---

*Part 3. My read on Mojo at 1.0 beta, from building a real program in it rather than reading release notes. Where it's matured, where it bites, and the one thing that decides whether it fits your project at all.*

<p><img class="brand-logo" src="/assets/images/brand/mojo-wordmark.svg" alt="Mojo" width="200"></p>

*Mojo and the Mojo flame are trademarks of Modular Inc.; shown here for identification.*



## What Mojo is (and what it isn't)

When Mojo was announced in May 2023, a lot of Python programmers read the pitch the way I did: a Python-like language with C++-like performance, a superset you could adopt without rewriting anything. A drop-in replacement. The Holy Grail.

It never worked out that way for me - the friction associated with the compiled, statically type languages was visible at the surface. The distance between code that *looks* like Python and code that *runs* any of my Python code stayed large.

The 1.0 beta is a refined version of that 2023 sketch. The way to read it is not "Python but fast." It's a Python-*family* systems language: static types, value ownership, traits, generics, compile-time parameterization, GPU and kernel authoring, with Python interop as a bridge rather than a foundation. Judged as a drop-in Python replacement, it loses on ecosystem size. Judged as a compiled control-plane language sitting close to a model runtime, it's a credible choice today. Ignis is the second test, and that framing matters for everything below.

If you're coming from Python, here's the shape of the difference at a glance:

| Aspect | Python (CPython) | Mojo 1.0 beta |
|---|---|---|
| Execution | interpreted bytecode | compiled to native code, ahead of time (MLIR/LLVM) |
| Variables | dynamic assignment | `var`, optionally typed |
| Functions | `def`, dynamic | `def`, statically typed and checked |
| Records | classes: dict-backed, heap | `struct`s: static layout, stack or inline (classes exist too) |
| Memory | garbage collected | ownership + borrow checking, no GC |
| Parallelism | GIL-bound | no GIL; SIMD-first types; CPU and GPU from one source |
| Ecosystem | vast | young; CPython interop is the bridge |
| Speed | the baseline | compiled native code, but a real number needs a benchmark |

One caveat on that table: "compiled native" describes how the code runs, not how much faster it is. I benchmarked none of Ignis's harness code, so the headline speedups you'll see quoted elsewhere aren't numbers I can stand behind. (And if you're arriving from older Mojo material, a couple of keywords have changed since - there's a short note further down.)

## New to Mojo? A five-minute primer

*If you already write Mojo, skip to [Why Python is in the loop at all](#why-python-is-in-the-loop-at-all). This section is for getting a newcomer oriented enough to read the rest.*

**Where it comes from.** Mojo is from [Modular](https://www.modular.com/), the company Chris Lattner founded (he created LLVM, Clang, Swift, and MLIR). It's built on **MLIR** and compiles *ahead of time* to native code - so unlike CPython there's no interpreter in the running program. The pitch is one language that spans high-level application logic *and* low-level, GPU-class kernels.

**It looks like Python, but it's statically typed and compiled.** A program has an entry point and prints like you'd expect:

```mojo
def main():
    var name = "world"          # `var` declares a variable
    print("hello,", name)
```

You build it with `mojo build hello.mojo -o hello` and run `./hello`. (There's also `mojo run`, but - see [Part 1](./01-what-ignis-is.md) - anything that brings up MAX must be *built* first.)

**Functions are statically typed.** The function keyword is `def`, but unlike Python's it's checked: you annotate argument and return types, and the compiler holds you to them. Type annotations are real, not hints.

**Structs with value semantics.** You model data as `struct`s - value types whose layout the compiler fixes - and opt into copy/move behavior explicitly. (`class` exists too, for the rarer case you need Python-style dynamism.) For example:

```mojo
struct Order(Copyable, Movable):
    var id: String
    var total: Float64
```

**Ownership is the headline feature.** Every value has one owner; the compiler tracks it. Argument conventions say how a function touches its argument - `read` (borrow, the default), `mut` (mutable borrow), `var`/`out` (it takes ownership) - and `^` *transfers* ownership:

```mojo
def __init__(out self, var outputs: List[String]):
    self.outputs = outputs^      # take ownership of `outputs`, no copy
```

This is why you'll see `.copy()` and `^` dotted through real Mojo: collections like `List` aren't implicitly copyable, so every additional owner is spelled out. It's more typing than Python - and it's what makes the code allocation-honest.

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

That `[...]` bracket is **compile-time parameterization** - it can carry types (`[G: Greeter]`) or values (`[n: Int]`), and the compiler specializes a fresh, fast version per instantiation, with no runtime dispatch. This single feature is the spine of Ignis: `process_turn[E: Engine]` is generic over the model backend, so the live model and the no-model test double run the exact same control-plane code.

**Numbers are SIMD-first.** Mojo's scalar types are really vectors of width one (`SIMD[DType.float32, 4]` is four floats in a register), which is what lets the same language express GPU/CPU kernels - the territory of [Part 4](./04-max-the-platform.md)'s custom ops.

**Python is one import away.** When a battery is missing, Mojo embeds CPython and calls it:

```mojo
from std.python import Python

def use_numpy() raises:
    var np = Python.import_module("numpy")
    print(np.array([1, 2, 3]).sum())   # real CPython, in this same process
```

That escape hatch is the entire model path in Ignis - and, as the rest of this part argues, both its superpower and its catch.

**Getting it.** The toolchain ships as the `modular` package (it bundles the `mojo` compiler *and* MAX). Two common ways in: `pixi`/`magic` (Modular's conda-based project manager) or a plain `uv venv` + `uv pip install modular …` from Modular's nightly index. Either gives you `mojo build` and the `max` Python library in one go.

**What the official manual emphasizes.** Modular's own [Mojo manual](https://mojolang.org/docs/manual/) frames the language around writing *high-performance code for CPUs and GPUs*, and it organizes that around a few pillars worth knowing by name:

- **Systems programming** - pointers, explicit memory management, and the value-ownership model above.
- **Metaprogramming** - compile-time evaluation, parameterization, generics, and traits (the `[...]` machinery), so abstractions can cost nothing at runtime.
- **Hardware portability** - one language targeting CPU *and* GPU.
- **Python interoperability** - call Python from Mojo *and* Mojo from Python, so adoption is incremental rather than all-or-nothing.

Note the framing: the docs position Mojo as *complementary to Python through interop*, not as a drop-in superset - which squares exactly with what Ignis ran into below.

That's enough syntax to read on. Before the assessment, two practical detours for anyone making the jump - how to ramp up, then how to port - and a short note on the keywords that have changed.

## Ramping up from Python to Mojo

If you are a Python developer starting on Mojo today, this is the order I'd suggest - roughly the order Ignis taught me.

1. **Write something small from scratch before you port anything.** A parser, a CLI, a numeric kernel - code with no Python baggage to fight. You learn the compiler's rules fastest when nothing is being dragged across. Ignis started as the harness core and grew from there.
2. **Spend your first real effort on ownership.** It's the one idea with no Python analogue, and it shapes every signature you write. Get `read`/`mut`/`var`/`out` and the `^` transfer into your fingers until choosing `.copy()` versus `^` is automatic; structs and traits all sit on top of it.
3. **Default to value types.** Reach for `struct` and let the compiler fix the layout, and drop to a dynamic `class` only when you truly need reference semantics. The Python habit to unlearn is "everything is a dictionary."
4. **Learn traits and `[...]` parameters early.** They do the job Python's duck typing does, but at compile time. A generic `def f[T: Trait]` gives you reuse with no runtime dispatch; in Ignis a single trait (`Engine`) is what lets the same code run with a model or without one. Btw, does anyone remember interfaces from Java?
5. **Keep CPython in reach, on purpose.** `from std.python import Python` is there for the batteries Mojo hasn't grown yet. Use it deliberately for the missing piece, and notice every time you do - that count is your honest measure of how Mojo-native the project really is.
6. **Lean on the manual and the release notes.** The language still moves, so the [Mojo manual](https://mojolang.org/docs/manual/) and [release notes](https://mojolang.org/releases/) are the only sources that track the current spelling; tutorials more than a year old will steer you wrong (the keyword note below has the specifics).

The mindset under all of it: Mojo reads like Python, but underneath it's a systems language - ownership, static types, compilation, SIMD. Come to it for those and the friction makes sense.

## Porting Python code to Mojo: a checklist

Ramping up is the mindset; this is the mechanics - the construct-by-construct habit-changes I made translating Python into Ignis. Work top to bottom when you're porting a file.

1. **Install the toolchain, and build before you run.** Get Mojo through the `modular` package (`pixi`/`magic`, or `uv pip install modular` from the nightly index); source files end in `.mojo`. Then compile with `mojo build` and run the binary rather than `mojo run` - Ignis has to, because JIT crashes when MAX initialises ([Part 1](./01-what-ignis-is.md)), and it's a fine default anyway.
2. **Declare with `var`, and reach for types.** Where Python infers everything, a Mojo binding is a `var`, plus a type wherever it helps the compiler (`var total: Int = 0`). Ignis types its timeline fields this way; the annotation is what lets the compiler fix the layout.
3. **Write `def`, and give it types.** Functions are `def`, and in Mojo they're statically typed - annotate the arguments and the return, and the compiler checks them. Every function in Ignis is a `def`, down to the MAX custom-op kernels in [Part 4](./04-max-the-platform.md).
4. **Turn dynamic classes into `struct`s.** A Python class is a dictionary with methods attached; a `struct` is a fixed record whose layout the compiler knows. Port your data holders to `struct`s and declare what they support (`Copyable`, `Movable`). `SessionEntry` is a struct, which is why Ignis's timeline is a real `List[SessionEntry]` and not parallel `String` columns. (`class` still exists for the rare case you need runtime dynamism; I never reached for it.)
5. **Learn four ownership marks: `read`, `mut`, `var`/`out`, and `^`.** This is the one genuinely new idea. A function argument is `read` (an immutable borrow, the default), `mut` (a mutable borrow), or `var`/`out` (it takes ownership), and `^` moves ownership across explicitly. Day to day it means a `List` never silently copies - you write `.copy()` or hand it over with `^`.
6. **Keep Python for the batteries you can't replace.** `from std.python import Python` embeds CPython in the same process and hands you any module - NumPy, transformers, whatever you need. In Ignis that bridge *is* the model path: Mojo drives MAX's Python API through it. Indispensable, and also the thing that caps how Mojo-native the project can be (the next section is about exactly that).
7. **Reach for SIMD when you own a hot loop.** Numeric types are SIMD vectors - a scalar is just width-1 - so a tight numeric loop you would otherwise push to NumPy you can write directly in Mojo. Ignis does this for the retrieval dot-product, with no FFI and no separate kernel file.

## Reading older Mojo

Most code from 2025-era tutorials still compiles against 1.0 beta. The keyword that doesn't is `fn`: it was deprecated in [v0.26.2](https://mojolang.org/releases/v0.26.2/) (March 2026) and is gone in the 1.0.0b2 nightly this blog was built against, so wherever an older guide writes `fn`, write `def` - now strict and statically typed by default. One smaller note: the current spelling for a compile-time binding is `comptime` (since [v0.25.7](https://mojolang.org/releases/v0.25.7/)), where older code wrote `alias`; both still work, with `comptime` preferred. The full release notes are at [mojolang.org/releases](https://mojolang.org/releases/).

## Why Python is in the loop at all

A fair question lands immediately: if MAX is Modular's Mojo-first runtime and Ignis is Mojo, where does Python enter? It enters at the API you call. The kernels, the graph compiler, and on-device execution are compiled, and Mojo is the language they're written in. But the developer-facing surface - load a model, build a request, run `generate` - ships as a Python library, `max.pipelines`. There's no Mojo-native call that loads Qwen3-8B and generates from it. So Ignis takes the only door available and embeds CPython.

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

So the headline needs its qualifier. In-process is accurate: the model runs in the same OS process as the harness, which is what removes the REST hop. Pure Mojo it is not. The path is `Mojo → embedded CPython → MAX's Python API → native kernels`. Mojo is MAX's kernel language; it isn't its orchestration language yet. Removing CPython entirely would need a Mojo-native inference API that doesn't exist, and that sets the ceiling on how Mojo-native a project like this can be right now.

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

`process_turn[E: Engine]` specializes at compile time - no dynamic dispatch on the hot path - which is what lets `make test` exercise the real logic without a model. The tool boundary uses the same shape (`decode_tool_call[C: ToolCodec]`).

**Structs and ownership are clean.** The timeline is an actual `List[SessionEntry]` - a list of structs, not parallel `String` columns dressed up as records. Types declare `Copyable, Movable` explicitly, and the ownership annotations make data movement easy to read:

```mojo
def __init__(out self, var outputs: List[String]):
    self.outputs = outputs^      # this backend takes ownership, and says so
```

For deterministic harness code - session state, encoders, parsers, policy checks - this is where Mojo delivers on the systems-language pitch.

Structs are also why Mojo has a second record keyword at all, and the reason is worth spelling out. Python gives you one tool, `class`, and it is always maximally dynamic: every attribute is a dictionary entry, instances live on the heap, dispatch happens at runtime, and you can monkey-patch after the fact. That flexibility is exactly what makes attribute access slow and memory layout unpredictable. A `struct` is the other trade - fixed fields, a layout the compiler nails down, value semantics, stack or inline allocation, static dispatch - so the dynamism you usually don't need is simply absent and the compiler can optimize around it. Mojo keeps a `class` form for the cases that genuinely want reference semantics and Python-style dynamism, so you opt into that cost rather than paying it by default the way Python makes you.

In Ignis that distinction is concrete. A `List[SessionEntry]` is a contiguous run of fixed-layout records, not a list of pointers to heap dictionaries, and the flat `Float32` buffer behind the vector index is the same idea at its limit: one allocation, indexed arithmetic, no per-element object. I didn't benchmark any of this, so I make no speed claim (Part 2's honest column holds). But this is where the speed *would* come from, and it's why the timeline could be the obvious data structure rather than a hand-tuned one.

**SIMD is real, and reachable from ordinary code.** The retrieval index (`ignis_vec.mojo`) ranks documents with a hand-written dot-product kernel sitting right next to the harness code:

```mojo
comptime W = 8                        # a compile-time width
var p = self.data.unsafe_ptr() + row * self.dim
var q = query.unsafe_ptr()
var acc = SIMD[DType.float32, W](0)
var j = 0
while j + W <= self.dim:
    acc = p.load[width=W](j).fma(q.load[width=W](j), acc)
    j += W
var s = acc.reduce_add()              # + a scalar tail for dim % 8
```

No FFI, no numpy round-trip, no separate kernel file: the language that owns the session timeline also owns the vector math. This is the first pure-Mojo compute in Ignis that's load-bearing rather than a demo - the live RAG ranking runs through it - and it's the concrete payoff of "scalars are SIMD width-1" from the primer.

## Where it bites

Mature isn't the same as comfortable, and most of the friction is the ownership model doing its job, which still costs you coming from Python.

- **`List` isn't implicitly copyable.** Every additional owner needs an explicit `.copy()` or a `^` transfer: `var msgs = base_msgs.copy()` where Python would just hand over the reference.
- **Strings are codepoint-indexed**, so string surgery that's casual in Python takes more code. The JSON escaper, `strip_think`, and the FNV-style hash all walk `text.codepoints()` and compare integer code points instead of slicing. Open-ended `s[i:]` fails; you reach for `String.split(...)`. It's the correct Unicode-safe primitive, and it's more typing.
- **Deprecation churn is real.** The language is still moving fast enough that sample code from even a year ago often won't compile; the specific keyword changes are gathered in the *Reading older Mojo* note earlier. Mojo improves *by* churning, and you feel it.
- **A dev-build serializer bug cost me real time.** EmberJSON's `to_string` won't compile on this build (`'self' abandoned without being explicitly destroyed`). `parse` and value access are fine, so Ignis works around it by holding the parsed substring and re-`parse`-ing instead of serializing. Nearby cuts: `Object`/`Value` aren't `ImplicitlyCopyable` (borrow with `ref`), and accessors return library types you coerce back with `String(...)` / `Int(...)`.
- **Error messages are serviceable, not a strength.** The failures that cost me most weren't type errors with a clear location. They were cases where the compiler accepted the code and the *runtime* fell over - which diagnostics can't catch.

## Batteries not included

This is the wall my original, bigger port hit, and it's what actually decides whether Mojo suits a given project.

**There is no standard-library JSON.** An agent harness is JSON end to end - messages, tool schemas, tool-call payloads, event logs - and the Mojo stdlib parses none of it. Ignis brings in EmberJSON for parsing and hand-writes JSON construction with a manual escaper. The blunt rule I wrote into the codebase - *use EmberJSON, never hand-roll JSON parsing* - is only sensible because the battery is missing.

**The service ecosystem is young.** HTTP servers, async patterns, JSON Schema validation, database drivers, tracing, provider SDKs - none are at Python parity. A call center treats those as the spine, not extras, which is why my full port stalled and Ignis narrowed to a focused harness.

And here's the tension at the heart of the language today. Python interop is the escape hatch, and leaning on it everywhere quietly gives up the drop-in story. Mojo can import CPython, so you're never fully blocked - the entire model path in Ignis is `std.python` reaching into MAX. But if every missing battery is answered with "call Python," you haven't replaced Python, you've wrapped it. Interop is a migration path and a runtime bridge. It is not a native ecosystem.

## My verdict on the language

For what I built - a compiled, deterministic control plane running in-process with a model - Mojo at 1.0 beta is ready enough to ship. Traits, generics, ownership, and structs carried the harness. If your problem is a state machine near a model - a parser, a policy gate, an encoder, a tool loop - Mojo is a credible choice today.

For the original goal - a drop-in replacement for a batteries-included Python application - it isn't ready, and there's no use pretending otherwise. No stdlib JSON, a young service ecosystem, and the constant pull toward interop the moment you leave the happy path. The ecosystem is three years old; that's the explanation, not a design flaw.

What would help, roughly in the order it cost me: a standard-library JSON module; a serializer that compiles on a stable release; a documented, supported in-process MAX-from-Mojo API, so the integration traps become the platform's problem instead of folklore; and a stable channel that doesn't ship dev-build surprises. None of these are research. They're maturation. I went back to Mojo to find out whether it had become *Python but fast*. It hasn't - and after Ignis I think that was the wrong test. The framing that fits is the one in [Part 4](./04-max-the-platform.md): a compiled control plane sharing one runtime with the model, where the value is proximity.

---

*Previous: [What Was Achieved](./02-what-was-achieved.md). Next: [MAX, the Platform](./04-max-the-platform.md). [Series index](./ignis.md).*
