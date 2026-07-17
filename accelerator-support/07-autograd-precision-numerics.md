---
title: "Part 7 - Autograd, Precision, and Numerical Validation"
header:
  overlay_image: /assets/images/accelerator/diagram-numerical-trust.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-numerical-trust.svg
sidebar:
  nav: "accelerator"
---

*Part 7 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
Numerical validation spans instruction behavior, operator accuracy, gradients,
model quality, and training convergence. Each level needs explicit acceptance
criteria.*

## Numerical acceptance criteria

Precision, rounding, accumulation order, fused operations, denormal handling,
approximation functions, and parallel reduction order all affect floating-point
results. Two accelerator implementations can satisfy the same contract while
differing in low-order bits. Agreement on a small test can still conceal divergence
over a long training run.

The platform must define acceptable behavior per workload and level. An elementwise
operator may use an absolute and relative tolerance. A reduction may need an error
bound that grows with size. A classifier may be judged by task metrics. Training
requires loss curves, gradient statistics, and convergence over enough seeds to
separate a backend error from ordinary stochastic variation.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-numerical-trust.svg" alt="A numerical validation pyramid from instruction edge cases through operators, gradients, fused subgraphs, model activations and logits, task quality, and long-run convergence.">
  <figcaption>Validation proceeds from instruction edge cases to long-run workload behavior, with failures localized at the lowest level that diverges.</figcaption>
</figure>

## Dtype semantics

The dtype contract covers encoded values and operation behavior:

- Encoded range and special values.
- Input conversion and rounding mode.
- Multiply, accumulation, and output precision.
- Saturation or overflow behavior.
- Treatment of subnormals, NaNs, and infinities.
- Reduction order and intermediate precision.
- Transcendental approximations.
- Whether behavior changes under a fast-math mode.

Low-precision matrix formats often multiply in one format, accumulate in another,
and scale at a tensor, channel, block, or tile granularity. Framework dtype,
checkpoint representation, compiler types, kernel layouts, and hardware
instructions must describe the same scheme.

## Autograd backend requirements

PyTorch's autograd engine records a graph and schedules derivative work. The
accelerator backend supplies correct forward and backward operators, saved-tensor
semantics, stream ordering, gradient dtypes, and integration with compiled backward
graphs.

There are several ways an operator can acquire derivative behavior:

- A derivative formula expressed in existing PyTorch operations.
- A separately registered backward implementation.
- A custom autograd function.
- A compiler-generated backward graph through AOTAutograd.

Test each path. In-place operations and views are especially
sensitive because version counters and aliasing determine whether saved values are
valid. Higher-order gradients add another level of operator coverage.

An inference-only product can exclude gradients from its support contract and
reject backward use with a clear error. PyTorch enables autograd by default, so the
backend must define dispatch behavior for forward-only workloads as well.

## Automatic mixed-precision policy

AMP chooses which operations use lower precision and which stay in or promote to
FP32. The policy balances throughput, range, and numerical sensitivity. PyTorch's
accelerator integration exposes casting categories through
`AutocastPrivateUse1`, along with the dtypes supported by the device.

Training adds gradient scaling to avoid underflow. The complete path includes scale
updates, non-finite detection, optimizer interaction, distributed gradient
reduction, and checkpoint state. Inference still needs autocast policies that agree
with model conversion and kernel support.

The policy should be versioned and testable. Changing an operation from FP32 to
lower precision can improve a benchmark and alter model quality.

## RNG and determinism

Random-number behavior touches initialization, dropout, sampling, data loading,
stochastic rounding, and randomized algorithms. A backend needs generators,
seeding, state save and restore, stream-safe consumption, and defined behavior
under graph capture or recomputation.

Define determinism for a named build, device, algorithm set, and seed. PyTorch
documents that complete reproducibility is not guaranteed across releases or
platforms. Deterministic algorithms may be slower, but they reduce debugging and
regression cost.

The backend must also identify known nondeterministic operators and honor the
framework mode that requests deterministic alternatives or errors.

## Validation across system levels

**Instruction and conversion tests.** Exercise rounding boundaries, overflow,
special values, scaling, and every promised accumulation path.

**Operator reference tests.** Compare values, shapes, strides, errors, and
fallback state across dtypes and layouts. Include large reductions, adversarial
inputs, and random values near zero.

**Gradient tests.** Use analytical comparisons and finite differences where
appropriate. PyTorch provides `gradcheck` and `gradgradcheck`, with care required
for low precision and nondeterministic functions.

**Fused-subgraph tests.** Compare compiler fusion and tuned library paths with an
unfused reference. Many numerical changes enter through reassociation or reduced
intermediate precision.

**Model checks.** Compare layer activations, final logits, loss, generated tokens,
or task metrics. Layer-by-layer capture localizes the first divergence.

**Long-run qualification.** For training, compare convergence, stability, and
quality across seeds. For serving, run long contexts, sustained batching, cache
pressure, and repeated sampling.

## Tolerance review and failure artifacts

Record the reason for each tolerance. Valid reasons include dtype precision,
reduction length, approximation error, stochastic behavior, or an accepted fast
algorithm. Increasing a tolerance until a test passes loses the distinction between
expected numerical variation and a broken kernel.

Failure artifacts should retain the exact input, seed, device and software builds,
algorithm identity, compiler graph or IR, and the first mismatching values. Add
minimized reproducers to the permanent regression suite.

## Numerical modes and performance tradeoffs

Higher-accuracy or deterministic algorithms can cost throughput or memory.
Deterministic reductions may serialize work. Higher-precision accumulation consumes resources.
Fast transcendental approximations trade error for latency. The platform should
expose these choices through explicit modes or documented policies. Any build flag
that changes numerical behavior must be part of the published configuration.

Every benchmark artifact must state its numerical mode so performance comparisons
use equivalent quality requirements.

---

*Previous: [The Graph Compiler](./06-graph-compiler.md). Next: [Scale-Up and Scale-Out](./08-distributed-systems.md). [Series index](./accelerator-support.md).*

Sources: [PyTorch AMP integration](https://docs.pytorch.org/docs/stable/accelerator/amp.html); [PyTorch reproducibility](https://docs.pytorch.org/docs/stable/notes/randomness.html); [Gradcheck mechanics](https://docs.pytorch.org/docs/stable/notes/gradcheck.html); [Extending PyTorch](https://docs.pytorch.org/docs/stable/notes/extending.html); [PyTorch compiler FAQ](https://docs.pytorch.org/docs/stable/user_guide/torch_compiler/torch.compiler_faq.html).
