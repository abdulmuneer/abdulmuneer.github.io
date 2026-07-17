---
title: "Part 11 - Framework Boundaries and Vendor Stacks"
header:
  overlay_image: /assets/images/accelerator/diagram-framework-boundaries.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-framework-boundaries.svg
sidebar:
  nav: "accelerator"
---

*Part 11 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
PyTorch, JAX, and MAX hand programs to accelerator software at different points.
The NVIDIA CUDA, AMD ROCm, and Intel GPU software stacks show the drivers,
compilers, libraries, and tools required after each handoff.*

The first ten parts traced one path from the machine to a PyTorch user. PyTorch
integrates a device into its tensor and operator system. JAX hands a functional
program to a compiler and runtime plugin. MAX spans model graphs, compiled kernels,
and serving.

Each choice assigns the underlying contracts to different owners and exposes
failures at different layers. Every path requires a driver, compiler, kernels,
memory management, collectives, tools, packaging, and release engineering.
Comparing the framework handoffs with the vendor implementations shows who owns
each contract.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-framework-boundaries.svg" alt="Aligned PyTorch, JAX, and MAX paths. PyTorch exposes tensor, dispatcher, compiler, and device integration points. JAX lowers jaxpr to StableHLO and hands compilation and execution to a target compiler and PJRT plugin. MAX exposes inference graphs and Mojo custom operations over supported device backends. All three depend on drivers, compilers, kernels, collectives, tools, packaging, and qualification.">
  <figcaption>PyTorch exposes framework hooks, JAX exposes PJRT, and MAX 26.4 documents extensions above supported device backends.</figcaption>
</figure>

## Framework handoff points

### PyTorch integrates a device into tensors and operators

A PyTorch backend participates directly in tensor behavior. Storage, views,
strides, copies, factories, random numbers, streams, events, serialization,
autocast, autograd, errors, and operator dispatch all reach the device
implementation. `PrivateUse1` is the documented out-of-tree route. The backend
supplies device and runtime hooks, an allocator, a device guard, generators, and
the minimum factory, view, copy, and fallback operators under the reserved dispatch
keys. AMP, profiling, distributed, and compiler integration extend that base.
`PrivateUse1` is one reserved backend slot, so one process cannot host two
independent out-of-tree accelerator packages under separate `PrivateUse1`
identities.

The first useful coverage unit is usually an ATen operator and its variants.
Composite implementations and fallbacks help during bring-up. Performance-critical
paths later move to native kernels or compiler lowerings. Eager execution and
`torch.compile` exercise different contracts. A model may run eagerly even when
FakeTensor propagation, decompositions, graph capture, generated code, cache lookup,
or runtime loading fails in the compiled path.

Users get the familiar eager model, and missing coverage appears at named operator
boundaries. The out-of-tree path keeps device code outside PyTorch core. The vendor
owns compatibility with dispatcher and subsystem changes, its CI, and its release
matrix.

### JAX lowers through StableHLO and runs through PJRT

JAX traces a function written with `jax.numpy` and `jax.lax` into typed jaxpr.
Transformations such as `jit`, `grad`, and `vmap` interpret or rewrite primitives
at that level. The specialized jaxpr lowers to StableHLO. A target compiler
produces a device executable, and PJRT manages buffers and execution:

```text
Python function
  -> JAX primitives and transformations
  -> typed jaxpr
  -> StableHLO
  -> target compiler
  -> device executable
  -> PJRT buffers and execution
```

Programs composed from existing JAX primitives inherit the transformation rules
those primitives implement. A new primitive must define the rules required by its
support claim: abstract evaluation and lowering, plus eager execution, autodiff,
batching, effects, and sharding where applicable. A raw `jax.ffi.ffi_call` is
opaque to autodiff and batching. With sharded inputs it may cause all-gathers and
redundant execution unless the wrapper defines per-shard behavior. The current JAX
FFI guide uses experimental HiJAX primitives for these transformation rules.
Pallas provides custom kernels for supported GPU and TPU backends and remains
experimental.

StableHLO is the compiler-facing program contract. The target compiler handles
legality, layout assignment, fusion, scheduling, library selection, buffer
planning, code generation, and diagnostics. Coverage must span operation, dtype,
rank, layout, dynamic-dimension, aliasing, collective, and numerical-mode
combinations.

PJRT defines the device and execution interface. A plugin exposes clients, devices,
memory spaces, buffers, compilation, loaded executables, asynchronous readiness,
and execution. The plugin may call an XLA backend, or it may pair PJRT with a
separate MLIR-based StableHLO compiler as described by OpenXLA.

Sharded JAX programs split responsibility between compiler and runtime. The
compiler partitions the program; PJRT and the device runtime expose global and
addressable devices, topology, buffers, asynchronous execution, and the
communication and multi-process services used by the executable.

A PJRT shared library exports `GetPjRtApi`. JAX discovers a Python module through
the `jax_plugins` namespace or entry-point group and calls its `initialize()`
function. The current OpenXLA guide has that function call the private
`jax._src.xla_bridge.register_plugin` API and requires the plugin's PJRT C API
version to match `jaxlib`. Production support therefore needs one tested matrix
across JAX, `jaxlib`, PJRT, compiler, runtime, driver, firmware, and hardware.

### MAX spans graph construction, compilation, and serving

MAX begins with an inference graph. `max.graph` and `max.nn` construct it
explicitly; the eager-like interface stages operations into graphs while returning
concrete results. The compiler performs fusion, target specialization, scheduling,
and memory planning before MAX Engine executes the result.

Mojo custom operations are visible graph nodes. A custom operation registers with
`@compiler.register`, declares its inputs and outputs, supplies shape inference
where needed, and can use `DeviceContext` for memory, launch, and synchronization.
The implementation can share code across supported targets and specialize for the
selected architecture. MAX also packages model architecture registration,
tokenization, KV-cache management, batching, pipelines, and OpenAI-compatible
serving. Its public product surface centers on inference; general training and
autograd have no equivalent public contract.

These APIs extend an existing MAX device backend. PyTorch can call compiled Mojo
operations, including from `torch.compile`, at an operator or subgraph boundary.
A PyTorch device integration additionally requires tensor semantics, broad
operator coverage, autograd, distributed execution, profiling, and packaging.

{: .notice--info}
**MAX 26.4 publishes no documented third-party device-backend interface.** MAX
documents model, graph, operation, kernel, pipeline, and serving extensions. Mojo
documents architecture descriptors for GPU families already supported by its
compiler and runtime. The generated MAX 26.4 driver stub defines an `NPU` dispatch
class and mentions an “NPU plugin hook.” Modular publishes no ABI, registration
API, sample backend, versioning contract, or conformance suite for that hook.
Public sources therefore do not describe how an independent vendor implements a
new MAX device backend.

The public 26.4 material leaves compiler targeting, runtime ownership, plugin
versioning, libraries, and qualification unspecified for a new accelerator. Once
Modular supports a target, the MAX compiler, model runtime, pipelines, and serving
layer can sit above it.

## Framework integration contracts

| Concern | PyTorch | JAX | MAX |
|---|---|---|---|
| User model | Eager tensors, autograd, optional compiled regions | Array programs and functional transformations | Explicit or eager-like inference graphs |
| Main hardware boundary | Device hooks, dispatcher, kernels, and compiler backend | StableHLO compiler path and PJRT plugin | MAX compiler and runtime over supported targets |
| Early coverage unit | ATen operator and variants | StableHLO operation across dtype, shape, and layout combinations; then representative programs | Graph operation or Mojo custom operation |
| Custom operation work | Schema, metadata, device kernel, autograd, transforms, compilation | Primitive or FFI registration, abstract evaluation, lowering, explicit transformation and sharding rules | Graph registration, shape function, Mojo implementation, target specialization |
| Distributed model | ProcessGroup, DeviceMesh, DTensor, DDP, FSDP | Global arrays, `Mesh`, sharding, compiler partitioning | Supported data- and tensor-parallel inference; availability varies by model architecture |
| Public third-party device route | One `PrivateUse1` slot per process | PJRT C API plus a target compiler; current JAX registration is private and version-coupled | Generic device route unpublished in MAX 26.4 |
| Qualification emphasis | Tensor semantics, operator variants, eager and compiled parity | StableHLO coverage, transformation composition, PJRT and runtime behavior | Graph, kernel, runtime, and serving behavior per supported target |

Compilation failures surface differently in each framework. Default
`torch.compile` may split a callable at graph breaks and compile the resulting
regions. `jax.jit` raises tracing or concretization errors when data-dependent
Python requests a concrete value; remedies include static arguments, JAX
control-flow or callback constructs, or a smaller `jit` boundary. MAX can stage
small eager-like graphs or compile a larger module. Profilers and logs must
identify the executed path, the point where compilation stopped, and any host
transfer or fallback.

## Vendor stacks below the framework handoff

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-vendor-stack-seams.svg" alt="Aligned NVIDIA CUDA, AMD ROCm, and Intel GPU stacks across PyTorch surface, programming and runtime layer, compiler artifact, libraries and collectives, kernel driver, and tools. Each column uses different interfaces and artifacts at corresponding layers.">
  <figcaption>CUDA, ROCm, and Intel XPU use different runtime APIs, device binaries, drivers, and libraries.</figcaption>
</figure>

CUDA separates the low-level Driver API in `libcuda` from the higher-level CUDA
Runtime API. Compilation commonly passes through NVVM IR and PTX; the toolchain or
driver produces target-native cubins. PTX is a vendor virtual ISA with documented
driver compatibility rules. cuBLAS, cuDNN, and NCCL supply tuned math, neural
network, and collective implementations. PyTorch's built-in CUDA backend connects
these pieces to its allocator, streams, graphs, AMP, compiler, profiler, and
distributed paths. Nsight Systems traces system activity, Nsight Compute profiles
kernels, and CUDA-GDB provides source-level debugging.

ROCm uses the Linux `amdgpu` driver and ROCr, the HSA user-mode runtime, beneath
HIP. HIP deliberately resembles CUDA at the source and runtime API level.
HIP-Clang lowers through LLVM's AMDGPU backend into code objects for selected
`gfx` targets. rocBLAS supplies BLAS kernels, MIOpen supplies neural-network
primitives, and RCCL supplies collectives.
PyTorch's ROCm build reuses the `torch.cuda` Python surface and the `cuda` device
string; `torch.version.hip` identifies the build. This preserves much Python source
code. AMD retains its own execution semantics, generated artifacts, wavefront
behavior, matrix instructions, kernel tuning, and release matrix.

Intel's Linux GPU path can use `xe` or `i915`, depending on the generation. Intel
Compute Runtime implements Level Zero and OpenCL. DPC++ supplies the SYCL
programming model, while Unified Runtime connects the compiler to device-specific
adapters. The compiler can emit SPIR-V for later device compilation or an
ahead-of-time native artifact. oneMKL and oneDNN provide math and neural-network
kernels. PyTorch exposes Intel GPU support through `torch.xpu` and currently maps
XPU collective use to the `xccl` backend. VTune profiles CPU and GPU execution,
and Intel Distribution for GDB debugs CPU and GPU code.

These stacks place different objects at roughly corresponding layers. CUDA
contexts and streams, HSA queues and signals, and Level Zero command queues and
lists carry different ownership, ordering, and error semantics. PTX, AMD code
objects, and SPIR-V have different producers, consumers, target assumptions, and
compatibility promises. A portable API must specify each mapping.

{: .notice--info}
**Gaudi uses a separate accelerator stack.** Intel Gaudi exposes the `hpu` PyTorch
device and uses SynapseAI for graph compilation and runtime services, HCCL for
collectives, and TPC tools for custom kernels. Intel GPU uses the `xpu` device with
SYCL and Level Zero.

## Portability claims and their evidence

| Dimension | Evidence required |
|---|---|
| Source | The same source compiles for each named target. |
| API | The application keeps the same calls and device abstractions. |
| Compiler IR | Another compiler accepts the saved program representation and its calling convention. |
| Binary | The same executable artifact runs on another device or generation. |
| Numerical | Rounding, accumulation, exceptional values, and accuracy meet the same declared contract. |
| Performance | The implementation keeps useful utilization across the target workload distribution. |

HIP preserves much of CUDA's source and API structure, and PyTorch carries part of
that compatibility into Python. AMD binaries and their tuning remain target
specific. SYCL standardizes a C++ programming model, and SPIR-V standardizes an
intermediate representation. Device-specific extensions, subgroup widths, matrix
operations, memory behavior, native modules, libraries, and cost models remain.

StableHLO standardizes the high-level program passed from framework to compiler.
The vendor runtime, kernel libraries, layout selection, and collective transport
remain target responsibilities. PJRT standardizes framework-to-device interaction,
with the plugin supplying those implementations. Mojo kernel source can be shared
across supported targets and specialized at compile time. MAX needs target-specific
code generation and the selected device runtime.

`jax.export` is JAX's compatibility-bearing serialization path. Lowered objects
are process-local; raw `compiler_ir()` output is a debugging artifact. Exported
custom calls require a target covered by JAX's custom-call compatibility rules.

Every portability claim should name its dimension and evidence. Successful
compilation on two targets establishes source portability only. Binary
compatibility, numerical behavior, and performance require separate tests.

## Sharing one compiler and runtime across frameworks

A new accelerator can serve several frameworks through one internal compiler and
runtime. The shared layer exposes devices, memory spaces, queues, events, modules,
topology, and errors. Separate adapters can implement PyTorch device hooks and
PJRT. The public MAX 26.4 material does not define a third-party adapter contract.

The shared layer needs its own semantics. If one internal `stream` type maps to
CUDA streams, HSA queues, and Level Zero command lists, its contract must specify
context ownership, visibility, synchronization, capture, and failure behavior.
Each framework adapter then documents its mapping to that contract.

The product requirements determine which adapter comes first:

- PyTorch `PrivateUse1` supports early eager execution, operator-by-operator
  bring-up, and access to the PyTorch training ecosystem.
- JAX with PJRT fits a compiler-centered product whose target compiler accepts
  StableHLO and whose runtime plugin provides devices, buffers, asynchronous
  execution, and the services required by sharded executables.
- MAX becomes available to an inference product after Modular supports the target;
  the graph, kernel, model-runtime, and serving layers can then run above that
  backend.

Qualification covers both the adapter and the shared stack. PyTorch coverage
includes tensor semantics, operator suites, gradients, compiled graphs,
distributed workloads, and ecosystem tests. JAX coverage includes PJRT
C API behavior tests, JAX backend tests selected for the supported surface,
composed `jit`, `grad`, `jvp`, and `vmap`, sharding and multi-process cases, custom
calls, and export compatibility where promised. MAX coverage includes explicit
and eager-like graphs, built-in and Mojo operations, placement, compilation,
pipeline execution, KV-cache behavior, batching, serving, and PyTorch
interoperability.

Each qualification record should retain the generated artifact, loaded libraries,
fallback state, compiler cache key, topology, profiler trace, numerical mode, and
exact version matrix. The framework adapter determines where diagnostics first
become useful. Release readiness also covers the underlying driver, compiler,
runtime, libraries, firmware, and hardware contracts.

---

*Previous: [Qualification and Release](./10-productization.md). [Series index](./accelerator-support.md).*

Sources: [PyTorch accelerator integration](https://docs.pytorch.org/docs/stable/accelerator/index.html); [PyTorch operator registration](https://docs.pytorch.org/docs/stable/accelerator/operators.html); [PyTorch PrivateUse1 tutorial](https://docs.pytorch.org/tutorials/advanced/privateuseone.html); [PyTorch HIP semantics](https://docs.pytorch.org/docs/stable/notes/hip.html); [PyTorch XPU](https://docs.pytorch.org/docs/stable/xpu.html); [PyTorch distributed backends](https://docs.pytorch.org/docs/stable/distributed.html); [JAX architecture](https://docs.jax.dev/en/latest/about.html); [JAX ahead-of-time compilation](https://docs.jax.dev/en/latest/aot.html); [Jaxpr](https://docs.jax.dev/en/latest/jaxpr.html); [JAX primitives](https://docs.jax.dev/en/latest/jax-primitives.html); [JAX FFI](https://docs.jax.dev/en/latest/ffi.html); [Pallas](https://docs.jax.dev/en/latest/pallas/); [JAX control flow](https://docs.jax.dev/en/latest/control-flow.html); [JAX sharding](https://docs.jax.dev/en/latest/notebooks/explicit-sharding.html); [JAX multi-process execution](https://docs.jax.dev/en/latest/multi_process.html); [JAX export](https://docs.jax.dev/en/latest/export/export.html); [StableHLO](https://openxla.org/stablehlo); [PJRT API](https://openxla.org/xla/pjrt/cpp_api_overview); [PJRT integration](https://openxla.org/xla/pjrt/pjrt_integration); [PJRT examples](https://openxla.org/xla/pjrt/examples); [MAX development and parallelism](https://docs.modular.com/max/develop/); [MAX Graph](https://docs.modular.com/max/develop/graph/); [MAX custom operations](https://docs.modular.com/max/develop/custom-ops/); [MAX GPU custom operations](https://docs.modular.com/max/develop/build-custom-ops/); [MAX pipelines](https://docs.modular.com/max/develop/pipelines/); [Mojo GPU target information](https://docs.modular.com/mojo/std/gpu/host/info/); [Mojo DeviceContext](https://docs.modular.com/mojo/std/gpu/host/device_context/DeviceContext/); [Mojo custom operations in PyTorch](https://docs.modular.com/max/develop/custom-kernels-pytorch/); [MAX 26.4 driver interface](https://github.com/modular/modular/blob/max/v26.4/max/python/max/_core/driver.pyi); [CUDA Runtime and Driver APIs](https://docs.nvidia.com/cuda/cuda-runtime-api/driver-vs-runtime-api.html); [NVVM IR](https://docs.nvidia.com/cuda/nvvm-ir-spec/index.html); [PTX ISA](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html); [ROCr](https://rocm.docs.amd.com/projects/ROCR-Runtime/en/latest/index.html); [HIP Runtime](https://rocm.docs.amd.com/projects/HIP/en/develop/how-to/hip_runtime_api.html); [HIP compiler support](https://rocm.docs.amd.com/projects/llvm-project/en/latest/LLVM/clang/html/HIPSupport.html); [ROCm compatibility matrix](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html); [Intel Xe driver](https://docs.kernel.org/gpu/xe/); [Intel Compute Runtime](https://github.com/intel/compute-runtime); [Unified Runtime](https://intel.github.io/llvm/design/UnifiedRuntime.html); [Level Zero](https://oneapi-src.github.io/level-zero-spec/level-zero/latest/core/INTRO.html); [DPC++ architecture](https://intel.github.io/llvm/design/CompilerAndRuntimeDesign.html); [Gaudi PyTorch integration](https://docs.habana.ai/en/latest/PyTorch/PyTorch_Model_Porting/Porting_PyTorch_Models_to_Gaudi.html); [HCCL](https://docs.habana.ai/en/latest/API_Reference_Guides/HCCL_APIs/index.html); [Gaudi TPC](https://docs.habana.ai/en/latest/TPC/index.html).
