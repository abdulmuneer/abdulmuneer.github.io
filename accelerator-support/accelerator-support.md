---
title: "Building Software Support for a New AI Accelerator"
permalink: /accelerator-support/
header:
  overlay_image: /assets/images/accelerator/hero-accelerator.svg
  overlay_filter: 0.48
sidebar:
  nav: "accelerator"
toc: false
author_profile: false
---

A usable accelerator product needs a software stack that executes real workloads
correctly, efficiently, and predictably. The required software spans model APIs,
framework semantics, compilers, kernels, runtimes, drivers, firmware, memory, and
interconnects, and must operate within the chip's power and thermal limits. A
failure anywhere in that path can erase hardware gains.

The series starts with the behavior expected from `model.to(device)` and
`torch.compile(model)`, defines the hardware execution model, and traces the
software required to expose that hardware as a supported framework target. The
scope is cross-functional:
framework engineers, compiler and kernel teams, driver and firmware developers,
collective-library and networking engineers, media-engine teams, performance and
reliability engineers, and the architects responsible for compute, memory,
packaging, and process technology all shape the result.

The final part compares where PyTorch, JAX, and MAX place their public hardware
boundaries, then aligns the CUDA, ROCm, and Intel XPU stacks at the driver,
runtime, compiler, library, and framework seams.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-whole-system.svg" alt="A full accelerator product stack running from user workloads through frameworks, compiler, kernels, runtime, driver, firmware, compute, memory, and fabrics, with validation crossing every layer.">
  <figcaption>Workload performance depends on every layer shown here and on the interfaces between them.</figcaption>
</figure>

## Scope of accelerator support

“Supports PyTorch” claims compatibility across tensor semantics, operator coverage,
compilation, numerics, distributed execution, packaging, profiling, and failure
handling. Tensor allocation is an early bring-up gate. Production training and
serving also require existing models to continue working across framework
upgrades, with diagnosable failures.

Interface semantics include tensor strides, storage, offset, dtype, device,
aliasing, and mutation; stream ordering and visibility; and collective ordering,
progress, topology, and failure behavior.

High-level graphs retain model meaning until target information is available.
Later representations introduce layout, tiling, memory spaces, and parallelism.

Registry presence establishes availability. Correctness across shapes, dtypes,
layouts, gradients, and dynamic cases requires tests. Workload and benchmark
results also need numerical comparison, fallback accounting, compile and transfer
costs, and a pinned software stack.

## Articles

- [Part 1 - The Support Contract](./01-the-support-contract.md) defines the levels
  hidden inside “supports PyTorch” and the evidence required at each one.
- [Part 2 - The Hardware-Software Contract](./02-hardware-software-contract.md)
  covers compute, memory, fabrics, fixed-function engines, packaging, lithography,
  power, and the information software needs from the chip.
- [Part 3 - Driver, Runtime, and Memory](./03-driver-runtime-memory.md) follows a
  process from device discovery through command submission, allocation, streams,
  events, faults, resets, virtualization, and profiling hooks.
- [Part 4 - Tensors, Dispatch, and Operators](./04-tensors-dispatch-operators.md)
  explains storage and view semantics, dispatch keys, schemas, native kernels,
  decompositions, metadata implementations, and fallbacks.
- [Part 5 - Kernel Libraries](./05-kernel-libraries.md) covers tiling, data
  movement, matrix instructions, attention, sparsity, low precision, autotuning,
  and the irregular and small-shape cases that determine workload coverage.
- [Part 6 - The Graph Compiler](./06-graph-compiler.md) traces Python through
  capture, guards, decompositions, AOTAutograd, scheduling, progressive lowering,
  target code generation, caching, and diagnostics.
- [Part 7 - Autograd, Precision, and Numerical Validation](./07-autograd-precision-numerics.md)
  covers backward support, AMP, accumulation, RNG, determinism, reference
  comparison, gradient checks, and training convergence.
- [Part 8 - Scale-Up and Scale-Out](./08-distributed-systems.md) connects physical
  topology to collective libraries, ProcessGroup, DeviceMesh, DTensor, parallel
  strategies, checkpointing, overlap, and failure recovery.
- [Part 9 - Training, Inference, and Media Engines](./09-domain-engines.md) shows
  how the common platform branches into different products, including serving
  runtimes and fixed-function video pipelines.
- [Part 10 - Qualification and Release](./10-productization.md) assembles
  the qualification gates, ecosystem matrix, compatibility policy, packaging, CI,
  observability, regression systems, release ownership, and maintenance processes.
- [Part 11 - Framework Boundaries and Vendor Stacks](./11-pytorch-jax-max-vendor-stacks.md)
  compares framework integration boundaries and traces their lower-stack
  implementations through CUDA, ROCm, and Intel XPU.

## Cross-team dependencies

The boundaries are organizational as well as technical. A matrix instruction
affects compiler legalization, kernel tile shapes, numerical qualification, and
performance counters. A new HBM configuration changes the allocator, the serving
capacity model, thermal behavior, and collective overlap. A page-fault mechanism
needs hardware support, firmware policy, a kernel driver, runtime APIs, framework
behavior, and tests that distinguish migration from a hang.

Cross-team work begins before tape-out. Hardware and software architects need an
explicit contract while the machine is still changing. Kernel and compiler teams
need simulators, emulators, and performance models before production silicon.
Framework engineers need to identify semantics whose cost determines platform
viability. Reliability engineers need error-injection coverage before release.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-team-contracts.svg" alt="A ring of collaborating teams: chip architecture, packaging and process, firmware and driver, runtime and memory, kernels and compiler, framework, distributed systems, domain engines, and validation.">
  <figcaption>Accelerator support depends on testable contracts shared across the participating teams.</figcaption>
</figure>

## Evidence policy

The series separates four kinds of statement:

1. A specification or API describes an intended contract.
2. Source inspection shows how one implementation represents that contract.
3. A focused test establishes behavior for a named build, device, dtype, and shape.
4. A workload result establishes end-to-end behavior for a named configuration.

Specifications and source inspection guide implementation. Release claims require
focused tests and workload results. Vendor figures are identified as vendor figures,
and fast-moving product details stay out of the central argument when a stable
interface provides sufficient evidence.

---

*Start with [Part 1 - The Support Contract](./01-the-support-contract.md). [Back to the blog home](../index.md).*
