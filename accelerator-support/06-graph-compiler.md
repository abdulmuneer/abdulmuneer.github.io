---
title: "Part 6 - The Graph Compiler"
header:
  overlay_image: /assets/images/accelerator/diagram-compiler-pipeline.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-compiler-pipeline.svg
sidebar:
  nav: "accelerator"
---

*Part 6 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
Graph compilation captures PyTorch programs, preserves their observable behavior,
and lowers them through staged representations into legal device code and memory
operations.*

## Graph-level optimization

Eager PyTorch executes operators as the Python program reaches them, which supports
interactive programming and debugging. Separate launches, materialized
intermediates, local layout choices, and per-operator memory planning can limit
performance.

Compilation optimizes a graph region across operator boundaries. It can fuse work,
specialize to useful facts, choose layouts jointly, reuse memory, overlap transfers,
and generate kernels for combinations absent from a static library. Every
transformation must preserve Python and PyTorch semantics.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-compiler-pipeline.svg" alt="The PyTorch compilation pipeline from Python through Dynamo capture and guards, FX, functionalization and decompositions, AOTAutograd, Inductor scheduling, target dialects, LLVM or device code generation, runtime loading, and cache.">
  <figcaption>Each lowering stage commits decisions once the required information is available.</figcaption>
</figure>

## Graph capture and guards

TorchDynamo observes Python execution and extracts FX graph regions. The compiled
result is guarded by assumptions about Python values, tensor properties, module
state, and other facts used during capture. When a guard fails, the system may
compile another version. Unsupported behavior can create a graph break, run in
Python, and allow capture to resume later.

Graph coverage varies at runtime with the inputs, guards, graph breaks, and cache
state. An accelerator backend needs tooling that reports each of these.

Dynamic shapes add symbolic dimensions and constraints. Static specialization can
improve code quality and may trigger repeated compilations. Fully dynamic lowering
can limit tiling, vectorization, or library selection. Specialize facts that improve
performance and keep workload-varying dimensions symbolic.

## Graph normalization before target lowering

Captured programs still contain mutation, views, composite operators, and training
semantics. Compiler stages normalize these behaviors:

- Functionalization represents mutation in a form suitable for graph transforms
  while preserving observable behavior.
- Decompositions express broad operators through a smaller primitive set.
- Fake or metadata execution propagates shape, dtype, stride, and alias facts.
- AOTAutograd constructs forward and backward graph regions for compiled training
  and partitions saved state between them.

Accelerator support must cover these stages for mutation, dynamic control, and
training. Qualification should include ordinary PyTorch programs that exercise all
three.

## RMSNorm compilation path

RMSNorm provides a compact example of the compiler contract. It reduces across the
normalized dimensions, applies an epsilon and reciprocal square root, broadcasts
the resulting scale, and optionally multiplies by a learned weight. The path
exercises reduction precision, broadcast semantics, fusion, layout, code
generation, and runtime attribution.

The semantic outline makes the computation type explicit:

```text
x_acc = cast(x, opmath_dtype)
eps_acc = eps if provided else finfo(opmath_dtype).eps
mean_square = mean(x_acc * x_acc, normalized_dimensions, keepdim=True)
y_acc = x_acc * rsqrt(mean_square + eps_acc)
if affine: y_acc = y_acc * weight
y = cast(y_acc, x.dtype)
```

For real floating inputs in PyTorch's current contract, FP16, BF16, and FP32 use
FP32 as the opmath type, while FP64 uses FP64. Complex inputs use the
corresponding complex opmath type and its real epsilon. The backend must preserve
PyTorch's normalized dimensions, epsilon rule, cast placement, computation and
accumulation types, output and weight dtype behavior, affine behavior, and empty or
unusual-shape behavior.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-rmsnorm-walkthrough.svg" alt="An instantiated RMSNorm module moving through torch.compile, Dynamo guards and an FX graph, FakeTensor metadata, decomposition, AOTAutograd, Inductor fusion and layout planning, Triton, C++ or Inductor vendor exits, runtime launch, profiler correlation, and eager or reference validation with fallback and host-transfer accounting.">
  <figcaption>Validation traces the source operation to its device launch and compares the result with an independent reference.</figcaption>
</figure>

The path proceeds through eight stages:

1. **Capture the Python program.** A user executes an instantiated
   `torch.nn.RMSNorm` module inside a `torch.compile` region. Dynamo produces an
   FX graph and guards the facts used to specialize it. Those facts may include
   input device, dtype, rank, sizes, strides, module state, and the normalized
   shape. A failed guard can select a different cached graph or trigger
   compilation.
2. **Establish metadata.** FakeTensor execution propagates the output's shape,
   dtype, device, and layout facts without allocating real input data. A symbolic
   batch or sequence dimension should remain symbolic if no later decision needs
   its value. The normalized width may need a guard when it controls a reduction
   schedule.
3. **Expose the computation.** The backend can lower an RMSNorm operator directly,
   or decompose it into opmath casts, multiply, mean reduction, epsilon addition,
   reciprocal square root, broadcast multiply, affine multiply, and output cast.
   Either form carries the same semantic obligations. For training, AOTAutograd
   also needs a valid backward graph and saved-state policy.
4. **Plan fusion and layout.** Inductor can consider folding the square into the
   reduction and applying the normalization and weight without materializing full
   intermediate tensors. A producer or consumer may join the region if aliasing,
   precision, and resource constraints allow it. Generated code determines whether
   the reduction and epilogue share one kernel.
5. **Choose a compiler integration.** Current Inductor paths commonly generate
   Triton for supported GPUs and C++ with OpenMP for CPUs. An accelerator that
   integrates with Inductor can add target code generation or lower a region to
   an external kernel or vendor library. A custom Dynamo backend is a separate
   route: it receives the FX graph and returns an equivalent callable directly,
   bypassing Inductor for that region. Each boundary needs explicit capability and
   failure reporting.
6. **Choose tiles and resources.** The schedule selects a one-pass or multi-pass
   reduction, vector width, rows per program, lane assignment, local-memory use,
   register budget, and launch geometry. Normalized width, alignment, dtype,
   available SRAM, and occupancy affect the choice. Bounded autotuning may choose
   among legal variants.
7. **Launch through the runtime.** The wrapper loads a generated module or resolves
   a library entry point, obtains workspace, binds data pointers, strides, shapes,
   and scalars, selects the framework stream, and submits the launch. Its cache key
   must include the guards and target properties that made the artifact valid.
8. **Validate and attribute execution.** Profiler data should connect the Python
   region and FX nodes to the generated kernel or external call and then to the
   device launch.
   Compare compiled results with eager PyTorch and an independent higher-precision
   reference across dtypes, shapes, strides, zero and extreme values, explicit and
   default epsilon, affine modes, and gradients where promised. Use a documented
   tolerance per dtype. Record graph breaks, recompilations, host transfers, and
   fallbacks. Treat silent eager execution as a failed compiler-path test.

## Intermediate representations and lowering stages

A compiler uses several representations to separate concerns:

1. A graph representation preserves tensor operations and model structure.
2. A loop or tensor-program representation exposes iteration, fusion, and layout.
3. A tiled representation maps work to blocks, lanes, matrix fragments, and
   memory spaces.
4. A target representation exposes legal instructions, address spaces, and calling
   conventions.
5. Machine code commits register allocation, scheduling, encoding, and relocation.

MLIR calls the movement between such levels dialect conversion. A conversion
target defines which operations and types are legal; rewrite patterns and type
converters turn illegal forms into legal ones. LLVM's target layer performs the
same kind of work closer to the instruction set: legalizing types and operations,
selecting instructions, allocating registers, scheduling, and emitting code.

Tensor-level optimization can remain shared across devices. Target-specific layers
handle matrix instruction selection and memory-space mapping for each instruction
set and memory hierarchy.

## Legality, correctness, and profitability

{: .notice--info}
**Legality:** the target can represent the transformed program. **Correctness:**
the transformed program preserves PyTorch's observable behavior.
**Profitability:** the measured benefit includes conversions, launches, workspace,
and compile cost. Accept a compiler decision after all three checks pass.

Legality asks whether the proposed form satisfies target constraints:

- Are dtypes and vector widths legal?
- Is local memory within the device limit?
- Do barriers cover every producer and consumer?
- Can dynamic dimensions satisfy tile and alignment constraints?

Correctness asks whether the legal form still means the same thing:

- Does a fused region preserve mutation, alias order, and exception behavior?
- Are reduction order, accumulation dtype, rounding, and special values within the
  numerical contract?
- Does a layout change preserve every visible stride, view, and copy obligation?
- Does specialization cover its guards without miscompiling other inputs?

Profitability includes the costs around the kernel. Cost models estimate memory
traffic, occupancy, instruction throughput, launch overhead, layout conversion,
workspace, transfer overlap, and library performance. Measure important choices
with autotuning within bounded search spaces, and retain the unfused or library path
when measurements favor it.

Report legality failures with the violated constraint, correctness failures with a
reduced reproducer, and profitability failures with the compared alternatives and
measurements.

## Layout planning across a graph

Tensor programs often admit several physical layouts. Layout affects coalescing,
matrix instruction compatibility, vectorization, communication, and whether a
transpose becomes metadata or a copy. Choosing it independently per operator can
insert conversions that dominate the graph.

Layout planning crosses fusion and sometimes distributed sharding. A
producer may accept a locally inferior layout because it is the consumer's native
form. A collective may operate on a shard layout that changes the next kernel's
tile. Compiler and library interfaces should carry layout descriptors explicitly
across this boundary.

## Runtime integration for generated code

After lowering, the backend must compile or assemble target code, load it, allocate
workspace, bind constants, launch it on the right stream, and preserve errors and
profiling identity. Ahead-of-time compilation moves some of that work out of the
request path. JIT compilation can specialize more aggressively. The runtime
contract applies to artifacts from either mode.

Cache correctness depends on guards, target capability, compiler build, options,
and tuning results. Cache operations need atomic publication and corruption
handling because many workers may compile the same artifact concurrently.

## Compiler diagnostics and reproducers

Diagnostics should answer:

- Where did the first graph break occur?
- Which guard caused recompilation?
- Which decomposition introduced an unsupported primitive?
- Which pass changed the result?
- Why was a fusion rejected or selected?
- Which layout conversions were inserted?
- What target constraint made an operation illegal?
- Which generated kernel, cache key, and source graph produced a device fault?

Compiler developers need pass-by-pass IR dumps. Users need a compact causal report
and a command that produces a complete reproducer. MLIR's pass infrastructure
includes timing, instrumentation, failure signaling, and crash reproducers.
Accelerator compilers should expose equivalent timing, instrumentation, failure
reports, and crash reproducers.

## Compiler backend qualification

A compiler backend is ready to claim support when it passes:

1. Eager-versus-compiled result comparison.
2. Static and dynamic shape workloads.
3. Mutation, aliasing, and view cases.
4. Graph-break and fallback accounting.
5. Training graphs where promised.
6. Cache reuse and invalidation tests.
7. Compiler crash and timeout containment.
8. Performance tests that include compile cost and steady state.

---

*Previous: [Kernel Libraries](./05-kernel-libraries.md). Next: [Autograd, Precision, and Numerical Validation](./07-autograd-precision-numerics.md). [Series index](./accelerator-support.md).*

Sources: [`torch.compile`](https://docs.pytorch.org/docs/stable/generated/torch.compile.html); [Dynamo core concepts](https://docs.pytorch.org/docs/main/user_guide/torch_compiler/compile/programming_model.dynamo_core_concepts.html); [Fake tensor](https://docs.pytorch.org/docs/main/user_guide/torch_compiler/torch.compiler_fake_tensor.html); [`torch.nn.RMSNorm`](https://docs.pytorch.org/docs/stable/generated/torch.nn.RMSNorm.html); [PyTorch RMSNorm native implementation](https://github.com/pytorch/pytorch/blob/v2.12.0/aten/src/ATen/native/layer_norm.cpp); [PyTorch compiler overview](https://docs.pytorch.org/docs/main/user_guide/torch_compiler/torch.compiler.html); [custom compiler backends](https://docs.pytorch.org/docs/stable/user_guide/torch_compiler/torch.compiler_custom_backends.html); [profiling `torch.compile`](https://docs.pytorch.org/docs/stable/user_guide/torch_compiler/torch.compiler_profiling_torch_compile.html); [Inductor provenance tracking](https://docs.pytorch.org/docs/main/user_guide/torch_compiler/torch.compiler_inductor_provenance.html); [PyTorch compiler troubleshooting](https://docs.pytorch.org/docs/main/user_guide/torch_compiler/torch.compiler_troubleshooting.html); [PyTorch compiler FAQ](https://docs.pytorch.org/docs/stable/user_guide/torch_compiler/torch.compiler_faq.html); [MLIR dialect conversion](https://mlir.llvm.org/docs/DialectConversion/); [MLIR pass infrastructure](https://mlir.llvm.org/docs/PassManagement/); [LLVM target-independent code generator](https://llvm.org/docs/CodeGenerator.html).
