---
title: "Part 3 - Driver, Runtime, and Memory"
header:
  overlay_image: /assets/images/accelerator/diagram-runtime-path.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-runtime-path.svg
sidebar:
  nav: "accelerator"
---

*Part 3 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
The driver and runtime expose hardware as a process-scoped resource with memory,
queues, synchronization, errors, and observable state.*

## Driver and runtime responsibilities

The operating system cannot hand a user process raw ownership of a large shared
device. It needs a kernel driver to enumerate hardware, establish protection,
manage interrupts and address translation, coordinate resets, expose telemetry,
and mediate privileged operations. Device firmware often owns boot, scheduling,
power, link management, or low-level recovery. A user-space runtime exposes
allocation, queue, event, module, and kernel-launch APIs over those mechanisms.

This boundary limits privileged code and separates kernel and user-space release
cadences. Kernel components need narrow, stable interfaces and cautious update
paths. Firmware can change behavior behind a stable host ABI when its compatibility
rules are explicit.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-runtime-path.svg" alt="A process calling a framework runtime, user-mode driver, kernel driver, firmware, and accelerator, with side paths for memory management, command queues, telemetry, and faults.">
  <figcaption>A kernel launch crosses several protection and compatibility boundaries before the device sees it.</figcaption>
</figure>

## Device lifecycle and identity

The runtime must answer basic questions consistently:

- Which devices are visible to this process?
- Which physical package, partition, NUMA node, and fabric endpoint does each
  logical device represent?
- Which driver, firmware, and ISA versions are active?
- Which capabilities does the runtime report directly?
- Can the process create multiple contexts, and what resources do they share?

Stable identity matters for cache keys, telemetry, scheduling, and recovery. A
framework index such as `device:1` identifies a device inside one process.
Correlating a retired memory page, a distributed rank, and a service incident
across reboots requires a stable physical identity.

Initialization also needs a clear failure model. Missing firmware, an unsupported
driver, a partition already owned by another tenant, and a device in reset are
different conditions. Collapsing them into “no accelerator available” sends users
to the wrong team.

## Command submission

Most accelerator work is asynchronous. A host thread records commands into one or
more queues, submits them, and continues. The device consumes those commands when
dependencies are ready. Streams or queues express ordering; events connect work
across queues and give the host a completion point.

The contract needs precision:

- Operations in one stream usually have an ordering relation. Work in different
  streams may overlap unless an event or resource dependency connects them.
- A host API can return before a kernel starts. Errors may therefore surface at a
  later synchronization point.
- Memory reuse must wait for device completion. Host call return can precede device
  completion.
- Graph capture and replay require stable command, memory, and synchronization
  behavior across invocations.
- Priority or preemption claims need a defined granularity and worst-case delay.

Frameworks build eager execution, autograd scheduling, distributed overlap, and
serving runtimes on these rules. A vague stream contract produces races that appear
several layers above their cause.

## Memory classes and placement policy

An allocation API hides physical pages, virtual addresses, residency, mapping,
pinning, migration, and lifetime. The runtime generally needs several allocation
classes:

- Device-local allocations for high-bandwidth access.
- Host allocations pinned for asynchronous transfer.
- Shared or unified allocations when supported by the platform.
- Peer-visible allocations for scale-up communication.
- Importable or exportable memory for graphics, media, networking, or another
  process.

Framework allocators cache blocks because device allocation is expensive and
synchronization-sensitive. The cache introduces its own contract: reserved versus
live bytes, fragmentation, stream-safe reuse, out-of-memory behavior, statistics,
and a way to release unused blocks. PyTorch's device-agnostic accelerator APIs now
include memory counters and cache-management hooks because these are user-visible
parts of the backend.

Virtual or unified memory hides explicit copies in source code while placement and
migration costs remain. Oversubscription trades capacity for page-fault and
transfer latency, which the profiler and runtime should report.

## Modules, kernels, and caches

The runtime loads compiled device code, resolves symbols, validates target
capabilities, allocates constant or executable memory, and launches entry points
with arguments and shared-memory requirements. JIT compilers add a persistent
cache whose identity may include:

- Source or graph hash.
- Compiler and framework builds.
- Target architecture and stepping.
- Driver or firmware compatibility boundary.
- Dtypes, shapes, layouts, specialization guards, and tuning result.
- Environment options that alter numerics or code generation.

Omitting a compatibility input can execute stale code. Including irrelevant inputs
increases recompilation and startup cost. Cache design affects correctness and
startup performance.

## Faults, RAS, and reset scope

Reliability, availability, and serviceability begin in hardware and firmware, but
the runtime carries their meaning to the application. Useful fault records identify
the device, engine, queue, process, virtual address where safe, memory bank or link,
severity, correction status, and reset scope.

Recovery depends on which state remains valid:

| Fault scope | Typical software consequence |
|---|---|
| One operation | fail the call; later work may continue |
| Queue or stream | cancel dependent work; rebuild the queue |
| Context | invalidate allocations and compiled module handles |
| Logical device or partition | quarantine and recreate the worker |
| Physical package or link domain | drain peers; reset or replace the node |

The exact mapping is device-specific. The requirement is that it be documented and
testable. Distributed systems need it to decide whether to retry a request, restart
a rank, or terminate the job.

## Isolation and virtualization

Multi-process service requires address-space isolation, command validation,
resource accounting, denial-of-service controls, and safe context teardown.
Partitioning and virtual-device features add scheduling and quality-of-service
questions: which caches, memory channels, copy engines, media blocks, and fabric
links are dedicated or shared?

Containers continue to share the host kernel and device driver, so the driver
remains a security and compatibility boundary. Packaging must constrain the
user-space stack to a compatible host stack, and orchestration must limit visibility
to the intended devices and capabilities.

## PyTorch integration points

A framework backend maps these runtime mechanisms into device guards, streams,
events, memory APIs, generators, hooks, profiling collectors, and Python-visible
device management. It also needs lazy initialization, thread-local current-device
and current-stream state, multiprocessing rules, and safe shutdown.

PyTorch's accelerator integration guide provides an official out-of-tree reference
called OpenReg and separates runtime integration from operator registration.
Stream ordering and allocator lifetime require separate tests from operator
correctness.

## Process creation and runtime initialization

`fork` duplicates a process address space while leaving initialized runtime state
tied to the parent. The child can inherit Python and C++
objects that refer to a context, allocator pool, command queue, event, driver file
descriptor, background thread, or locked mutex created in the parent. Treating
those objects as live child state can deadlock, corrupt allocator accounting, or
submit work through a context owned by another process.

The safe default for accelerator workers is `spawn` or `forkserver`. Initialize the
backend inside each child, select its device there, and create process-local
streams, generators, allocator state, and library handles. Keep the parent free of
runtime initialization before workers are created. This restriction includes
availability checks: PyTorch notes that an accelerator availability query usually
initializes enough runtime state to prevent a later safe fork. A backend can offer
a fork-safe discovery path, but discovery and runtime initialization must remain
separate contracts.

The runtime also needs a defined response when a process identifier changes after
initialization. A backend can reject every device call with an error that names the
pre-fork initialization and recommends `spawn`. A backend that
supports child reinitialization must invalidate all inherited device objects,
reopen its driver connection, rebuild contexts and allocator state, and document
which host objects remain usable. Copied device handles must fail explicitly unless
the backend performs full child reinitialization.

Multiprocessing tests should cover fork before initialization, fork after
initialization, `spawn`, `forkserver`, repeated child creation, child crashes, clean
child exit, and continued parent operation. Add DataLoader workers and distributed
launchers because they expose initialization order that a small runtime test can
miss.

## Runtime bring-up sequence

1. Enumerate and identify one device.
2. Allocate, map, copy, and free memory under stress.
3. Submit a no-op and observe completion.
4. Launch a small kernel and verify arguments and results.
5. Exercise multiple queues and event dependencies.
6. Add memory statistics, profiler correlation, and fault records.
7. Stress process exit, crashes, resets, and repeated initialization.
8. Add peer access, partitions, and multi-process isolation.

Validate these behaviors with a small runtime test suite and command-line
diagnostic before framework integration.

---

*Previous: [The Hardware-Software Contract](./02-hardware-software-contract.md). Next: [Tensors, Dispatch, and Operators](./04-tensors-dispatch-operators.md). [Series index](./accelerator-support.md).*

Sources: [PyTorch accelerator integration](https://docs.pytorch.org/docs/stable/accelerator/index.html); [`torch.accelerator`](https://docs.pytorch.org/docs/stable/accelerator.html); [PyTorch accelerator hooks](https://docs.pytorch.org/docs/stable/accelerator/hooks.html); [PyTorch accelerator semantics](https://docs.pytorch.org/docs/stable/torch.html#accelerators); [PyTorch multiprocessing best practices](https://docs.pytorch.org/docs/stable/notes/multiprocessing.html); [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/contents.html); [CXL specification and resources](https://computeexpresslink.org/).
