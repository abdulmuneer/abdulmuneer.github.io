---
title: "Part 1 - The Support Contract"
header:
  overlay_image: /assets/images/accelerator/diagram-support-ladder.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-support-ladder.svg
sidebar:
  nav: "accelerator"
---

*Part 1 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
Before discussing drivers or kernels, define what users are being promised.*

## Support claim

The phrase “the accelerator supports PyTorch” refers to a large engineering
program.

A user reads that sentence as behavioral compatibility. They expect tensors to
move to the device, familiar models to run, errors to identify their cause, saved
state to round-trip, mixed precision to behave predictably, and performance to
improve without a private rewrite of the model. Training users add gradients,
optimizers, distributed execution, and convergence. Inference users add model
loading, quantization, KV-cache capacity, batching, latency, and service stability.

An accelerator program needs a support contract that engineering teams and users
can test.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-support-ladder.svg" alt="Eight support levels: visible device, tensor semantics, eager operators, model execution, compiled execution, distributed workloads, production performance, and maintained product.">
  <figcaption>Each support level requires every lower-level contract.</figcaption>
</figure>

## Eight levels of support

**Level 0: device discovery and compatibility.** The package imports, the runtime finds a
compatible driver, devices can be enumerated and selected, and initialization
fails with a useful message when the stack is incompatible.

**Level 1: tensor semantics.** Allocation, views, strides, copies,
storage offsets, dtype conversion, scalar extraction, serialization, streams,
events, and random-number state obey their contracts. Model demonstrations depend
on these primitives.

**Level 2: eager operator coverage.** A stated operator set runs on the device
for declared dtypes, shapes, and layouts. Native implementations, composites,
decompositions, and fallbacks are reported separately. Unsupported cases fail
without corrupting state.

**Level 3: workload correctness.** Representative models execute end to end
without unintended host fallback. Activations, logits, losses, or task metrics
match a reference within a stated tolerance. Memory use and initialization are
bounded.

**Level 4: compiled execution.** Graph capture, metadata propagation,
dynamic shapes, mutation, custom operators, code generation, caching, and
recompilation behave on real programs. The compiled result matches eager execution
and produces a useful speedup after compilation cost is accounted for.

**Level 5: distributed execution.** Collectives, asynchronous progress,
topology discovery, sharded tensors, parallel training or inference, checkpointing,
timeouts, and rank failure have a qualified path.

**Level 6: performance qualification.** Published results name the model, input
distribution, precision, batch or concurrency, hardware, power mode, driver,
framework, compiler options, warm-up, measurement window, and fallback state.
Regressions are caught before release.

**Level 7: maintained compatibility.** Packages install on promised systems,
compatibility rules are documented, profiler and diagnostic tools work, security
and reliability updates ship, and a supported model retains a maintained execution
path after a framework upgrade.

## Backend paths for operator coverage

PyTorch currently documents more than 3,500 built-in operators when related
variants are counted. Those operators form the public API surface. A backend can
cover that surface through several implementation paths:

| Path | Coverage provided | What must stay visible |
|---|---|---|
| Native kernel or vendor library | target performance | qualified shapes, layouts, dtypes, algorithm selection |
| Composite implementation | reuse of existing operators | performance and semantic dependence on the component ops |
| Compiler decomposition | smaller primitive set | graph-only availability and decomposition stability |
| Host fallback | early functional coverage | transfer, synchronization, and performance cost |
| Explicit rejection | honest boundary | actionable error and capability query |

PyTorch's accelerator documentation recommends starting with foundational storage,
view, copy, and fallback operations, then expanding native coverage. Fallbacks must
be reported separately because they can preserve results while invalidating device
latency and throughput measurements.

## A machine-readable support matrix

A support entry records the full contract:

```text
operation: aten.softmax.int
device: accelerator generation 2
dtypes: fp32, bf16
ranks: 2 through 5
axis: any valid axis
layouts: contiguous; strided input through decomposition
execution: native for last-axis contiguous, composite otherwise
numerics: stated atol/rtol and accumulation mode
compile: eager and dynamic-shape compiled paths
autograd: first-order backward qualified
fallback: forbidden in performance runs
evidence: test suite, framework build, driver build, device stepping
```

Generate the matrix from tests and runtime capability data where possible. The
resulting artifact can block a release, feed compiler legality checks, guide model
placement, and explain host execution.

## Failure behavior and compatibility

The contract also specifies behavior for exhausted memory, kernel faults, cyclic
stream dependencies, incompatible drivers, and missing collective ranks. If the
runtime converts all of those into “device error,” the user cannot distinguish an
application error from a node failure.

The error path should preserve cause across layers:

```text
hardware event -> firmware record -> driver status -> runtime error
               -> framework exception -> profiler/trace correlation
```

Recovery is equally specific. Some faults can fail one operation. Others poison a
queue, context, device, node, or complete distributed job. The framework must know
which state can be reused. Reusing undefined state after a device fault risks
silent corruption.

## `model.to(device)` acceptance criteria

The call exercises device discovery, parameter and buffer copies, allocation,
dtype handling, module-specific state, serialization assumptions, and custom
operators. The following forward pass exercises dispatch, kernels, streams, RNG,
numerics, and memory lifetime. `torch.compile` adds capture, metadata, lowerings,
guards, code generation, and cache identity. Distributed execution adds failure
paths on other processes and machines.

The implementation plan consists of the lower-level contracts required to preserve
that simple interface.

## Support-contract exit criteria

Before hardware design work begins, the program needs answers to these questions:

- Which support level is promised for each release?
- Which workloads define success?
- Which behaviors are native, decomposed, or falling back?
- How are numerical tolerances chosen?
- Which failures invalidate a context or device?
- What compatibility window is supported?
- Which artifact proves each claim?

---

*Next: [The Hardware-Software Contract](./02-hardware-software-contract.md). [Series index](./accelerator-support.md).*

Sources: [PyTorch accelerator integration](https://docs.pytorch.org/docs/stable/accelerator/index.html); [PyTorch operator registration](https://docs.pytorch.org/docs/stable/accelerator/operators.html); [`torch.accelerator`](https://docs.pytorch.org/docs/stable/accelerator.html); [PyTorch profiler integration](https://docs.pytorch.org/docs/main/accelerator/profiler.html).
