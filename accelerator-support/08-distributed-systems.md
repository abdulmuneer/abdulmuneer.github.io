---
title: "Part 8 - Scale-Up and Scale-Out"
header:
  overlay_image: /assets/images/accelerator/diagram-distributed-stack.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-distributed-stack.svg
sidebar:
  nav: "accelerator"
---

*Part 8 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
Distributed support connects links, DMA, collective communication, sharded tensors,
and parallel workloads through one observable execution path.*

## Communication within and across nodes

Scale-up connects devices inside a server or tightly coupled rack domain. It may
offer peer memory access, high bandwidth, low latency, and a topology designed for
collectives. Scale-out connects nodes through a network with switches, NICs,
routing, congestion, and a larger failure domain.

The software stack must preserve this distinction. An algorithm that works well
across eight fully connected devices can stall across nodes. A topology-aware
collective can use a fast local reduction followed by a network phase based on the
actual distance between ranks.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-distributed-stack.svg" alt="A distributed accelerator stack from model parallel strategy through DTensor and DeviceMesh, ProcessGroup, collective library, runtime and DMA, scale-up fabric, NIC, switches, and scale-out network.">
  <figcaption>Each parallel strategy determines routes, buffers, synchronization, and failure domains in the physical system.</figcaption>
</figure>

## Physical communication prerequisites

Collective optimization depends on:

- Peer discovery and stable topology identity.
- Direct or staged memory-transfer paths.
- Registration and pinning for network-visible buffers.
- Address translation and isolation for DMA.
- Completion signaling that composes with device streams.
- NIC and accelerator affinity information.
- Link health, error counters, and reset behavior.

Direct accelerator networking can remove host copies and CPU intervention, but it
adds coordination across the driver, NIC, IOMMU, memory manager, runtime, and
collective library. Qualification must verify that actual allocation types and
topologies avoid hidden bounce buffers.

## Multi-NIC routing and affinity policy

A multi-NIC server exposes distinct paths through PCIe switches, CPU sockets,
coherent links, or an internal fabric. Network ports may lead to independent rails
with limited cross-rail bandwidth. CPU threads that drive progress have their own
NUMA affinity. The collective library needs the complete map.

Selection policy should prefer local accelerator-to-NIC paths, preserve rail
alignment when the fabric was wired for it, and use enough ports to reach the
expected aggregate bandwidth. It also needs an operator override and explicit
diagnostics for down ports, inconsistent cabling, and interfaces that are
administratively up but unreachable from other nodes.

Qualification should record the NIC, port, rail, CPU affinity, and transport
selected by every rank and channel. Run the same collective matrix with symmetric
nodes, asymmetric accelerator-to-NIC distances, one missing port, one slow rail,
and one failed rail. Report per-port traffic, errors, congestion, and throughput
alongside the aggregate result. Qualification expects explicit path-degradation
reports, policy-driven traffic redistribution, and a specific initialization error
when no valid route remains.

## Collective algorithm and route selection

All-reduce, all-gather, reduce-scatter, broadcast, all-to-all, and point-to-point
operations describe communication semantics. The library chooses routes and
algorithms: rings, trees, recursive schemes, hierarchical combinations, or
specialized hardware paths.

The choice depends on message size, rank count, topology, available channels,
contention, reduction dtype, and whether computation can overlap. Libraries such
as NCCL focus on communication primitives and expose asynchronous operations that
higher framework layers schedule.

Correctness includes ordering and progress. Two ranks issuing collectives in a
different order can hang. An operation that requires host polling has different
overlap behavior from one with device or NIC progress. The framework backend must
document these conditions.

## Worker launch and process-group bootstrap

Job control starts workers and supplies or arranges local rank, global rank, local
and global world sizes, and bootstrap coordinates before process-group
initialization. A static launch can pass a store or an initialization method
directly. An elastic launch adds a run identity and rendezvous endpoint; rendezvous
lets participants agree on membership and returns the shared store used to exchange
bootstrap information. Each worker then binds its local accelerator and calls
`init_process_group` with the selected backend, rank, world size, timeout, and
device information where the backend accepts it.

Initialization diagnostics should record this sequence for every worker:

- Launch identifier, host, process ID, rank, and world size. For an elastic job,
  include the rendezvous run identity and restart count.
- Local rank, local world size, logical device, and stable physical device ID.
- Backend, bootstrap endpoint, selected transport, and timeout.
- Accelerator, NIC, NUMA, and rail affinity used by the transport.
- Time spent in rendezvous, store exchange, and communicator creation.
- A topology digest and relevant driver, runtime, and communication-library versions.

Before model execution, verify that ranks are unique and contiguous, all workers
agree on world size and the launch generation where one is defined, local ranks
map to distinct devices, and topology digests match except for platform-permitted
asymmetry. An initialization timeout should identify whether the missing
progress was in peer discovery, store exchange, transport connection, or
communicator setup.

Process-group shutdown must be coordinated. Complete or abort outstanding work,
destroy subgroups and the default process group in an agreed order, and release
transport registrations before runtime teardown. Include repeated initialization
in the qualification matrix when the product promises it. Every implementation
must exit cleanly after one process-group lifetime.

## ProcessGroup backend integration

PyTorch's `torch.distributed` layer registers communication backends through the
`ProcessGroup` interface. A new accelerator can provide a third-party backend that
creates communicators, submits collectives, returns asynchronous work handles, and
maps completion to the device's stream model.

A registered `ProcessGroup` must provide the following behavior to higher layers:

- Correct tensor dtype, layout, and device handling.
- Group creation and destruction without leaks or global ordering bugs.
- Timeouts that interrupt or diagnose real work.
- Errors propagated consistently to every affected rank.
- Safe interaction with graph capture and compiled execution.
- Performance under concurrent compute and multiple communicators.

## Sharding with DeviceMesh and DTensor

A `DeviceMesh` represents ranks as an N-dimensional topology. DTensor associates a
logical tensor with placements such as shard, replicate, or partial on mesh
dimensions. Operators then propagate placements and insert redistribution or
collectives when required.

DTensor uses these placements to select redistributions and collectives. DTensor
qualification covers operator sharding rules, layout conversions, autograd,
checkpoint state, and the parallel strategies built on top, including tensor
parallelism and FSDP.

Validate identical mesh descriptions across ranks before executing collectives.
A mismatch can produce a silent hang, so diagnostics must report topology
construction and validation failures.

## Mapping parallelism to topology

**Data parallelism** replicates the model and reduces gradients. It is often
bandwidth-heavy during training and straightforward for independent inference
replicas.

**Fully sharded data parallelism** shards parameters, gradients, and optimizer
state, then gathers parameters around computation. It trades communication and
control complexity for memory capacity.

**Tensor parallelism** splits individual operations and may require collectives
inside each layer. It prefers high-bandwidth, low-latency scale-up fabrics.

**Pipeline parallelism** assigns layer ranges to stages and sends activations at
boundaries. It tolerates slower links better but introduces bubbles, scheduling,
and distributed state ownership.

**Expert parallelism** routes tokens to distributed MoE experts and combines the
results. Traffic is data-dependent and usually all-to-all-like.

A deployment may combine these parallel dimensions. Mapping choices depend on
model shape, memory, link hierarchy, batch or concurrency, and failure policy. The
planner requires link hierarchy and placement data in addition to the device count.

## DDP qualification

DistributedDataParallel qualification covers constructor synchronization, reducer
state, autograd integration, and model updates. With the default initialization
synchronization enabled, construction verifies parameter shapes and broadcasts
parameters and buffers from rank 0. Disabling it makes the caller responsible for
matching state. Construction also establishes reducer metadata.
Backward execution fills and reduces gradient buckets while autograd is still
running, and the reducer may rebuild their layout after observing the graph.
Unused parameters, delayed gradients, gradient accumulation, and uneven inputs
change the sequence of communication.

Qualify DDP against a single-device numerical reference and across several world
sizes. Cover:

- One process per accelerator, device assignment, and constructor-time synchronization.
- Bucket formation, overlap with backward compute, and reducer rebuild behavior.
- `no_sync` gradient accumulation, communication hooks, and mixed precision.
- Used and unused parameters, static and dynamic graphs, and activation checkpointing.
- Uneven input handling through the join protocol, including its gradient-scaling policy.
- Eager and compiled forward and backward execution.
- Checkpoint save and restore followed by identical optimizer progress.
- Rank failure during construction, forward, backward, and optimizer update.

Acceptance compares the complete model update: losses, reduced gradients, updated
parameters, collective order, exposed communication time, and peak memory. A
convergence failure introduced by enabling overlap indicates a backend or
scheduling defect.

## Compute and communication overlap

Compute and communication overlap requires compatible buffers, dependencies,
streams, progress mechanisms, and resource use. A kernel and a transfer may be
logically independent and still compete for memory bandwidth. A collective may
occupy compute units or copy engines needed by the model.

The profiler should report both collective duration and the portion exposed on the
critical path. Tuning for overlap includes work placement, bucket sizing, and a
measurement that concurrency improves the complete step.

## Collective failure and recovery

A missing rank, broken link, reset device, or stalled process can leave peers
waiting inside the same collective. Timeouts identify delay, but recovery needs a
shared decision about communicator, rank, and model state.

Failure tests and diagnostics should include:

- Heartbeats outside the blocked data path.
- Collective sequence and communicator identifiers.
- Flight-recorder traces for recent submissions and completions.
- Link and NIC telemetry correlated with ranks.
- Abort that reaches every participant.
- A policy for elastic restart or whole-job termination.
- Fault injection for process death, packet loss, reset, and slow ranks.

Torch Distributed Elastic applies membership changes between worker-group
generations. Rendezvous gathers a new set of workers and restarts the worker group.
The next generation can have a different world size and different rank assignments,
then constructs a new `ProcessGroup`.

During restart, terminate or fence the old communication generation, initialize a
fresh process group, reconstruct meshes and subgroups, restore model and optimizer
state, and rebuild samplers and RNG state for the new world. Record the rendezvous
generation and restart count in logs and checkpoints, then reject messages tagged
with an old generation. Algorithms that need a fixed world size must reject an
incompatible membership change or restart from a checkpoint that supports
resharding.

Distributed checkpoint APIs support recovery by saving local shards, optimizer
state, RNG state, and layout metadata without assembling the entire model on one
rank. Restore must tolerate a changed mesh when that is part of the support
contract.

## Distributed qualification criteria

Test collectives across message sizes and topologies, then test the framework
abstractions and real parallel workloads. Include concurrent communicators,
non-contiguous tensors where promised, mixed precision, graph capture, long runs,
and injected failure. Exercise fixed and elastic launches, initialization and
coordinated teardown, DDP, DTensor, FSDP, and the supported combinations of
parallel dimensions. Repeat the matrix with rail asymmetry and failed links.
Report topology, bootstrap time, selected paths, per-rail utilization, exposed
communication, and aggregate link throughput.

---

*Previous: [Autograd, Precision, and Numerical Validation](./07-autograd-precision-numerics.md). Next: [Training, Inference, and Media Engines](./09-domain-engines.md). [Series index](./accelerator-support.md).*

Sources: [PyTorch distributed](https://docs.pytorch.org/docs/stable/distributed); [PyTorch distributed accelerator integration](https://docs.pytorch.org/docs/main/accelerator/distributed.html); [PyTorch DistributedDataParallel](https://docs.pytorch.org/docs/stable/generated/torch.nn.parallel.DistributedDataParallel.html); [PyTorch elastic rendezvous](https://docs.pytorch.org/docs/stable/elastic/rendezvous.html); [PyTorch torchrun](https://docs.pytorch.org/docs/stable/elastic/run.html); [PyTorch DTensor](https://docs.pytorch.org/docs/stable/distributed.tensor.html); [PyTorch FSDP2](https://docs.pytorch.org/docs/stable/distributed.fsdp.fully_shard.html); [PyTorch Distributed Checkpoint](https://docs.pytorch.org/docs/stable/distributed.checkpoint.html); [NVIDIA NCCL documentation](https://docs.nvidia.com/deeplearning/nccl/); [NCCL performance and tuning](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting/performance_and_tuning.html).
