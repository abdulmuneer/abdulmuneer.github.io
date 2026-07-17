---
title: "Part 5 - Kernel Libraries"
header:
  overlay_image: /assets/images/accelerator/diagram-kernel-design.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-kernel-design.svg
sidebar:
  nav: "accelerator"
---

*Part 5 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
Kernel libraries map supported operators to the algorithm variants needed to use
the accelerator efficiently across workload shapes.*

## Workload bottleneck classification

Kernel libraries cover matmul, convolution, attention, norm, softmax, reduction,
sort, gather, scatter, and elementwise math. Each operator maps to several algorithm
families whose performance varies with shape, dtype, layout, sparsity, batch size,
cache state, and hardware generation.

A large square matrix multiplication can fill matrix units efficiently. A
decode-time matrix-vector product may spend most of its time reading weights. These
cases require different algorithm variants for the same mathematical operator.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-kernel-design.svg" alt="A kernel design map relating workload shape and arithmetic intensity to tiles, memory hierarchy, matrix instructions, synchronization, algorithm variants, and measured dispatch selection.">
  <figcaption>Kernel design maps a workload region to machine resources and selects a measured algorithm variant.</figcaption>
</figure>

## Arithmetic intensity and initial performance bounds

Arithmetic intensity is useful work per byte moved from a chosen level of memory.
If a kernel performs little arithmetic for every HBM byte, memory bandwidth bounds
it before peak compute matters. If it reuses each byte many times, instruction
throughput may dominate. The boundary changes with cache residency, fusion, tile
size, and batch.

The roofline model supplies an initial bound. Real kernels also pay for instruction
issue, address calculation, synchronization, register spills, bank conflicts,
occupancy loss, launch overhead, and tail handling. The model helps identify
memory-bound workloads before tuning matrix-instruction throughput.

## Tiling and resource use

A high-performance kernel partitions work so that data is reused near the compute
units:

1. A grid assigns output regions to workgroups or blocks.
2. Threads or lanes cooperate on a tile.
3. Data moves from global memory into registers or local SRAM.
4. Matrix or vector instructions consume fragments.
5. Partial results accumulate and are transformed or stored.

Tile choice balances reuse against resource pressure. Larger tiles can reduce
global traffic and increase matrix-unit efficiency while consuming registers and
SRAM. Resource use can reduce resident workgroups, expose latency, or make the
kernel illegal.
The best tile also depends on transpose flags, alignment, dimensions, and the
instruction shapes exposed by the chip.

Kernel teams need an accurate resource model from hardware and compiler teams.
Resource reports should include allocated register count and the source values
responsible for spills.

## Algorithm families and dispatch

A production matrix library holds multiple families: tiled matrix multiplication,
small and skinny cases, batched forms, grouped forms for MoE, sparse variants,
quantized paths, and fused epilogues. Attention libraries split prefill from decode,
causal from bidirectional, dense from paged KV, MHA from GQA or MLA, and often split
again by head dimension and hardware generation.

Dispatch selects among those families using a capability predicate and a cost
model. Some choices can be made statically. Others are autotuned on representative
inputs and cached. The tuning key must include every property that changes legality
or cost. Tuning must stay off the production request path.

Dispatch itself has a cost. Creating a library handle, constructing descriptors,
consulting a heuristic, searching algorithms, or missing a tuning cache can dominate
a small operation. Libraries should expose the selected algorithm and measure cold
setup, warm selection, and kernel execution separately. A valid cache key includes
the shape, layout, dtype, workspace limit, target, numerical mode, and any stream or
capture state that changes validity or cost.

## Low-precision storage, conversion, and execution

Low-precision support spans instructions, storage, scaling, conversion,
accumulation, framework integration, checkpoint handling, and validation:

- Storage and interchange formats.
- Scale representation and granularity.
- Quantize, dequantize, and conversion kernels.
- Accumulation and output precision rules.
- Calibration or training support where required.
- Fused consumers that avoid materializing expanded values.
- Reference tests for saturation, subnormals, NaNs, infinities, and rounding.
- Checkpoint loaders and framework dtype representation.

Block-scaled formats add layout constraints that can reach model conversion,
distributed sharding, and kernel tile shape. Conversion overhead can erase the
instruction-level gain.

## Irregular and shape-dependent operators

Model execution also depends on indexing, sorting, top-k, segmented reductions,
scatter, sampling, masking, and shape manipulation. These operations are often
sensitive to rank, stride, dynamic sizes, and atomics. They frequently determine
model coverage and can introduce hidden device-to-host synchronization.

Sparse MoE adds token routing, permutation, grouped expert computation, and result
combination. The matrix work may be efficient while bucketing or all-to-all
dominates. Kernel qualification must measure the subgraph as well as its largest
GEMM.

## Fusion legality and profitability

Fusing adjacent operations can keep intermediates in registers or SRAM, remove
launches, and expose algebraic simplifications. It can also increase register
pressure, duplicate work, reduce scheduling freedom, or create a large family
of specialized kernels.

A fusion decision requires legality and profitability tests. Legality covers
aliasing, mutation, numerical order, synchronization, and device limits.
Profitability compares saved movement and launches with resource growth and lost
reuse. The graph compiler usually owns the decision; kernel libraries provide
reusable templates and primitives for the candidate implementations.

## Kernel performance qualification

Microbenchmarks should report achieved bandwidth or operations, problem shape,
dtype, layout, warm-up, clocks or power mode, and algorithm. End-to-end tests add
framework and compiler versions, transfers, compilation, fallback state, and model
quality.

The regression system should retain distributions across favorable and awkward
cases:

- Common production shapes.
- Awkward tails and small batches.
- Cold and warm caches.
- Cold and warm library dispatch, including handle and descriptor setup.
- Contiguous and promised non-contiguous layouts.
- Concurrent compute and communication.
- Long runs that expose throttling or fragmentation.

Evaluate optimizations against the workload distribution. A benchmark gain that
slows that distribution fails product performance criteria.

## Kernel-library acceptance criteria

Each public kernel path should have:

1. A legality predicate.
2. Defined numerical behavior.
3. Workspace and synchronization requirements.
4. An algorithm or tuning identity visible to profiling.
5. Reference and stress tests.
6. Performance coverage over its intended region.
7. A fallback or error for inputs outside that region.

---

*Previous: [Tensors, Dispatch, and Operators](./04-tensors-dispatch-operators.md). Next: [The Graph Compiler](./06-graph-compiler.md). [Series index](./accelerator-support.md).*

Sources: [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/contents.html); [AMD CDNA architecture](https://www.amd.com/en/technologies/cdna.html); [Triton language and compiler](https://triton-lang.org/); [NVIDIA NCCL documentation](https://docs.nvidia.com/deeplearning/nccl/).
