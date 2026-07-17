---
title: "Part 2 - The Hardware-Software Contract"
header:
  overlay_image: /assets/images/accelerator/diagram-hardware-contract.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-hardware-contract.svg
sidebar:
  nav: "accelerator"
---

*Part 2 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
The chip is a hierarchy of compute, storage, and communication built inside
physical limits. Software needs a precise model of all four.*

## Data movement and usable throughput

Sustained workload throughput depends on memory and interconnect behavior alongside
arithmetic throughput.

An instruction consumes operands from registers. Registers are fed by local SRAM
or caches. Those are fed by package memory. Package memory is filled from host
memory, peer devices, storage, or a network. Every boundary has capacity,
bandwidth, latency, alignment, ordering, and sharing rules. A model is fast when
its schedule fits that hierarchy well enough to keep the expensive units occupied.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-hardware-contract.svg" alt="An accelerator package showing scalar, vector, matrix, and media engines connected to registers, local SRAM, cache, HBM, PCIe or CXL, scale-up links, and scale-out network, surrounded by power, thermal, packaging, and process limits.">
  <figcaption>The compiler and runtime target the matrix engine together with memory, control, media, and interconnects.</figcaption>
</figure>

## Execution engines and programming models

A modern accelerator can contain several execution classes:

- Scalar units for address arithmetic, control, and irregular work.
- Vector or SIMD units for elementwise and reduction-heavy kernels.
- Matrix units for dense or structured-sparse tensor operations.
- Load/store, copy, and asynchronous transfer engines.
- Fixed-function blocks for work such as video decode, encode, image processing,
  compression, encryption, or network packet movement.

Each execution class may use a distinct command format, memory model, preemption
policy, and firmware path. Exposing decoded video frames as tensors also requires
media APIs, surface formats, shared memory, synchronization, and framework bindings.

The architecture specification must include operand types, tile shapes,
accumulation and rounding behavior, exception rules, register use, latency,
throughput, issue constraints, and overlap rules. Compilers cannot select or
schedule the unit correctly without this information.

## Memory hierarchy and access contracts

Registers are fast and private but scarce. Local SRAM is programmable and useful
for tiling, but it consumes area and often requires explicit synchronization.
Caches reduce average movement while adding replacement and coherence behavior.
HBM provides enormous bandwidth but still sits far below peak matrix throughput in
bytes per operation. Host memory is larger and usually farther away. CXL can make
memory capacity and coherence more flexible; a coherent CXL address retains
remote-memory latency and bandwidth.

Software needs answers to practical questions:

- Which address spaces can an instruction read or write?
- Is virtual addressing per process, per device, or shared?
- What is coherent with the CPU and with peer devices?
- Can memory migrate on demand, and what reports a migration fault?
- What alignment and transaction sizes produce full bandwidth?
- Which atomics are supported in each memory scope?
- Can copy engines overlap compute, and how is completion observed?
- What happens when ECC corrects an error or a page is retired?

The allocator, compiler, runtime, and distributed library consume these answers
differently and must use a consistent contract.

## Fabric topology from die to data center

Communication starts on die and continues through the package, board, node, rack,
and data center. The relevant links may include an on-die network, chiplet fabric,
HBM interfaces, scale-up links between accelerators, PCIe or CXL to the host, and
Ethernet or InfiniBand between nodes.

Each fabric exposes different topology, addressing, ordering, congestion, and
progress behavior. Collective libraries, allocators, compilers, and serving
schedulers consume different parts of that contract, including the full latency
distribution.

Expose physical topology through runtime queries with stable device, link, NUMA,
and partition identities. Collective libraries and profilers can then map their
algorithms and traces to the actual fabric.

## Software effects of packaging and process technology

Lithography determines transistor density, frequency, leakage, cost, and yield.
Reticle limits encourage chiplets or multi-die packages. Advanced packaging makes
wide die-to-die links and co-packaged HBM possible. The package then faces power
delivery, signal integrity, thermal density, and cooling limits.

Those choices appear directly in software:

- Chiplets introduce non-uniform locality inside one logical device.
- More HBM stacks change capacity and bandwidth, but also package power and cost.
- Frequency throttling changes kernel and collective balance during a long run.
- Partitioning features change which compute, memory, and media resources are
  assigned to a process.
- A new stepping may retain the product name while changing instruction errata or
  scheduling guidance.

Peak specifications assume a qualified operating point. Production software must
also work when temperature, power policy, or reliability controls move the device
away from that point.

## Architecture specification for software

Before tape-out, software teams need a versioned machine contract containing at
least:

1. ISA and instruction semantics, including exceptional and low-precision cases.
2. Memory spaces, coherence, scopes, atomics, and ordering.
3. Command submission, synchronization, preemption, and context behavior.
4. Device and fabric topology, peer-access rules, and partitioning.
5. Fault, telemetry, performance-counter, and debug interfaces.
6. Firmware responsibilities and update compatibility.
7. Performance models for instructions, memory, and links.
8. Simulator or emulator behavior tied to a named hardware revision.

Tie the architecture specification to instruction tests, memory-model litmus tests,
compiler-generated microkernels, fault injection, and performance-counter checks.
These tests find ambiguities while hardware changes are still possible.

## Software evidence for hardware decisions

Framework engineers can identify costly semantics before the ISA is fixed. Kernel
teams can show which tile shapes waste registers or bandwidth. Compiler teams can
find an instruction with attractive peak behavior but no safe selection rule. Networking
teams can expose a missing ordering primitive. Media teams can identify a surface
format that forces a copy before inference. Reliability teams can show that a
fault record lacks enough identity to quarantine the damaged resource.

Hardware architects then decide whether to change the machine, expose a new
primitive, or assign the cost to software. Assigning it to software requires an
identified owner, a legal implementation path, and a measurable target.

---

*Previous: [The Support Contract](./01-the-support-contract.md). Next: [Driver, Runtime, and Memory](./03-driver-runtime-memory.md). [Series index](./accelerator-support.md).*

Sources: [AMD CDNA 4 architecture white paper](https://www.amd.com/content/dam/amd/en/documents/instinct-tech-docs/white-papers/amd-cdna-4-architecture-whitepaper.pdf); [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/contents.html); [PCI Express specification overview](https://pcisig.com/specification-overview/pci-express-base); [About CXL](https://computeexpresslink.org/about-cxl/); [NVIDIA Video Codec SDK](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.1/index.html); [NVDEC programming guide](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvdec-video-decoder-api-prog-guide/index.html).
