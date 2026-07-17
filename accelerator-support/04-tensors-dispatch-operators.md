---
title: "Part 4 - Tensors, Dispatch, and Operators"
header:
  overlay_image: /assets/images/accelerator/diagram-tensor-dispatch.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-tensor-dispatch.svg
sidebar:
  nav: "accelerator"
---

*Part 4 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
Framework integration exposes device memory through tensors whose storage, views,
dispatch behavior, gradients, precision policy, and graph metadata must follow
PyTorch semantics.*

## Tensor storage, metadata, and aliasing

A dense tensor commonly carries a storage reference, element dtype, device,
sizes, strides, and storage offset. Two tensors can describe different views of
the same allocation. A transpose can change strides without moving data. A slice
can change the offset. An in-place operation can change values observed through
another alias.

PyTorch compatibility includes these semantics. A backend may copy or decompose
non-contiguous inputs when it lacks a direct strided path, while preserving results
and reporting the cost. Incorrect alias handling can produce plausible values while
mutating the wrong view.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-tensor-dispatch.svg" alt="A tensor call flowing through schema, dispatch key set, metadata or fake implementation, and one of native kernel, composite, compiler decomposition, host fallback, or error paths.">
  <figcaption>Operator support includes schema, metadata, dispatch, execution, and derivative behavior.</figcaption>
</figure>

## Operators for tensor construction and storage

Framework tensor construction and manipulation depend on these operations:

- Allocate contiguous and explicitly strided storage.
- Create views with shape, stride, and offset.
- Resize or rebind tensor storage where the API permits it.
- Copy within the device and across device and host boundaries.
- Extract a scalar to the host.
- Create tensors from factories such as zeros, ranges, and random distributions.
- Serialize state and restore it onto a selected device.

PyTorch's accelerator documentation names operations such as `empty`,
`empty_strided`, `as_strided`, `view`, `resize_`, copy, storage `set_`, and scalar
extraction as early backend requirements. Fallback and many higher-level operators
depend on them.

## Rules for `out=` variants

An `out=` variant writes into storage chosen by the caller under rules that differ
from the allocating form. PyTorch's contract includes the following behavior:

- A zero-element output can be resized to the computed shape, stride, and memory
  format. Resizing a nonempty output with the wrong shape is legacy behavior that
  PyTorch is removing. A backend must follow the upstream behavior of the PyTorch
  version it supports, including its error.
- A correctly shaped output keeps its strides and memory format. Numerically, the
  result must match the allocating operation followed by a safe copy.
- The backend validates the output device and dtype before launch. For an operation
  without type promotion, result and output device and dtype must match.
  Promotion-aware operations may accept another output dtype when PyTorch's
  safe-cast rule permits it.
- Aliasing is operator-specific. An exact alias may be legal where the operation
  supports the corresponding in-place use. Partial input-output overlap and an
  internally overlapping output must be rejected unless that operator explicitly
  defines the case.
- PyTorch rejects automatic differentiation when an argument to an `out=` call
  requires gradients.

These cases belong in conformance tests. Include an empty output, a correctly
shaped non-contiguous output, the wrong device and dtype, an exact input alias,
disjoint views of one storage, a partial overlap, and an internally overlapping
view. A fresh contiguous result covers the allocating form; the `out=` variant must
also satisfy the storage, layout, casting, and alias rules above.

## Type promotion and autocast

Ordinary PyTorch type promotion determines the computation and result dtype from
tensor and scalar operands. It applies without an autocast context and includes
integers, booleans, floating-point values, and complex values. `torch.result_type`
reports PyTorch's standard promotion result. Individual operations can add
accumulator or result rules, as reductions often do.

Backend wrappers must preserve these rules before selecting a kernel. Tests should
mix dimensional tensors, zero-dimensional tensors, Python scalars, signed and
unsigned integers, real and complex inputs, and explicit `out=` tensors. AMP is a
separate dispatch policy: it casts selected floating-point operations inside an
autocast region. Base promotion behavior must pass independently of autocast.

## Dispatch-key selection

The dispatcher selects an implementation from an ordered key set that can include
the device backend, autograd, autocast, functionalization, batching, and other
framework modes. An accelerator integration must implement the relevant
interactions across that set.

For an out-of-tree device, `PrivateUse1` provides a backend dispatch key and
scaffolding. The integration normally includes:

- Backend kernels and fallbacks.
- An autograd path or explicit error for differentiable use.
- `AutocastPrivateUse1` policies for mixed precision.
- Device guard, generator, and serialization registration.
- Metadata implementations used by graph mode.
- Python APIs and automatic package loading.

`PrivateUse1` supplies extension points that let a backend integrate while tracking
upstream PyTorch. The vendor owns the behavior behind those extension points and
must keep pace with framework changes.

## Dispatcher and ATen dispatch-stub registration

The dispatcher and a native dispatch stub operate at different boundaries. The
dispatcher maps an operator schema and active dispatch key set to a backend
implementation. A backend can register that implementation with
`TORCH_LIBRARY_IMPL` or the corresponding Python library API.

Some existing ATen operators expose a second-stage `DispatchStub` inside their
native implementation. For a declared stub, `REGISTER_PRIVATEUSE1_DISPATCH` can
attach a device kernel while reusing surrounding ATen code, such as argument checks
or `TensorIterator` construction. Operators without a declared stub require another
integration route. Stub registration still participates in the operator schema and
dispatcher.

Planning should record whether each built-in uses direct dispatcher or stub
registration. Direct dispatcher registration owns more of the wrapper contract.
Stub registration reuses upstream machinery and requires the backend to track
changes to the stub signature and wrapper semantics. Custom operators still need a
schema and normal dispatcher registration.

## Backend paths for operator coverage

For layer normalization, the backend may dispatch to a tuned native kernel, call a
vendor library, expand the operation into reductions and elementwise primitives,
let the graph compiler fuse that expansion, fall back to the host, or reject the
case.

The choice can depend on rank, normalized dimensions, dtype, layout, alignment,
training mode, and whether the call is eager or compiled. Coverage is a predicate
over these properties for each operator instance.

Reserve native implementations for important shapes. Composite and decomposition
paths reduce the initial kernel count and provide a correctness reference. Host
fallback during bring-up introduces copies and synchronization. Explicit rejection
is preferable when fallback would exceed memory, violate latency, or hide an
unsupported training path.

## Operator schema requirements

An operator schema records argument and result types, optional values, mutation,
and alias relationships. Those annotations inform dispatch, autograd,
functionalization, export, and compiler transformations. An incorrect schema can
license an optimization that reorders a mutation or frees an aliased value too
early.

Custom accelerator operators require these registrations and tests:

1. A stable name and schema.
2. Device execution.
3. Metadata or fake execution for shape and dtype propagation.
4. Autograd behavior where differentiable.
5. Autocast behavior.
6. Functionalization, compilation, decomposition, and export behavior.
7. Tests for aliasing, mutation, errors, and serialization.

Device-function registration covers eager execution. Compilation also depends on
the schema, fake implementation, functionalization, and other registrations above.

## Functionalization of mutable custom operators

Compilers often functionalize a graph by replacing mutation with value-producing
operations and explicit updates. That transform depends on the operator contract.
A custom operator must name every mutated argument. A functional operator returns
fresh tensors. A conventional in-place operator mutates and returns its first
tensor. An `out=` custom operator mutates keyword-only output buffers, returns them
in schema order, and must ignore their previous values. With
`torch.library.custom_op`, the conventional in-place and `out=` forms use
`torch.Tag.inplace` and `torch.Tag.out`, respectively, together with an accurate
`mutates_args` declaration.

Other mutable custom operators cannot return an input or an alias of an input. If
arbitrary view or alias behavior falls outside the custom-op
API, split the operation or expose a contract the transform can represent. Marking
such an operator functional would hide an invalid contract during tracing.
`torch.library.opcheck` checks the schema, fake behavior, autograd registration, and
AOT dispatch behavior; its AOT test also exercises functionalization. Run it on
every supported device and on representative shapes, dtypes, strides, mutations,
and gradient settings.

## Metadata execution for graph compilation

Graph capture and compilation need to know output shapes, dtypes, strides, and
alias relationships without running the expensive device computation. Meta or fake
implementations provide that information. The metadata path must preserve dynamic
dimensions that remain symbolic.

Real and fake output metadata must agree. A fake contiguous output paired with a
transposed device view gives later scheduling and memory planning incorrect layout
information. Metadata tests should compare real and fake results across
representative inputs.

## `torch.export` requirements

`torch.export` support covers capture, stable operator identity, symbolic metadata,
serialization, and clean-process loading. A custom operator that appears in an
`ExportedProgram` needs a stable qualified name and a fake implementation that
preserves symbolic shapes and output metadata. The backend should export
representative static and dynamic models, inspect the captured operators and
constraints, and compare the exported module with eager execution.

Serialization needs a clean-process test. Save with `torch.export.save`, start a
new process, load the backend package so that its operators and device kernels are
registered, call `torch.export.load`, and execute on the accelerator. Also test the
diagnostic when the package or an operator registration is missing. The backend
package must supply the implementation named by a `.pt2` file.

PyTorch documents the saved export format as under active development. Release
qualification should cover the supported matrix of PyTorch version,
backend package, compiler, driver, and operator-set version. Claim cross-version
loading for tested version combinations.

## Autograd and autocast registration

PyTorch's autograd engine records operations and later invokes derivative behavior.
The accelerator vendor supplies forward and backward operator coverage, derivative
registrations, saved-tensor semantics, and compatible stream behavior.

Automatic mixed precision adds per-operator casting policy. Some operations can
run in lower precision, some should use FP32, and others promote inputs. PyTorch
exposes these policies through the autocast dispatch key for a new accelerator.
Select and validate them against numerical and performance targets.

## Fallback accounting

Backend telemetry should answer during or after a run:

- Which operations executed natively?
- Which decomposed into other device operations?
- Which caused a graph break?
- Which copied data to the host?
- Which synchronized a stream?
- Which implementation and algorithm handled each hot shape?

This accounting belongs in logs, profiler traces, test assertions, and benchmark
artifacts. Use the resulting records to prioritize coverage work.

## Framework acceptance tests

An early suite should combine storage and view tests, operator reference tests,
metadata parity, eager and compiled paths, autocast, gradients where promised,
serialization, and explicit no-fallback checks for performance workloads. It should
include empty tensors, odd sizes, non-contiguous inputs, overlapping views where
legal, invalid arguments, and out-of-memory behavior.

---

*Previous: [Driver, Runtime, and Memory](./03-driver-runtime-memory.md). Next: [Kernel Libraries](./05-kernel-libraries.md). [Series index](./accelerator-support.md).*

Sources: [PyTorch operator registration](https://docs.pytorch.org/docs/stable/accelerator/operators.html); [PyTorch `out=` contract](https://docs.pytorch.org/docs/stable/notes/out.html); [`torch.result_type`](https://docs.pytorch.org/docs/stable/generated/torch.result_type.html); [`torch.library`](https://docs.pytorch.org/docs/stable/library.html); [PyTorch PrivateUse1 tutorial](https://docs.pytorch.org/tutorials/advanced/privateuseone.html); [PyTorch AMP integration](https://docs.pytorch.org/docs/stable/accelerator/amp.html); [`torch.export` API](https://docs.pytorch.org/docs/stable/user_guide/torch_compiler/export/api_reference.html); [Extending PyTorch](https://docs.pytorch.org/docs/stable/notes/extending.html).
