---
title: "Part 9 - Training, Inference, and Media Engines"
header:
  overlay_image: /assets/images/accelerator/diagram-domain-engines.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-domain-engines.svg
sidebar:
  nav: "accelerator"
---

*Part 9 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
The shared platform supports several workload-specific runtimes. Training,
inference, and media pipelines impose different requirements on compute, memory,
scheduling, numerical behavior, and APIs.*

## Runtime requirements by workload

Device management, memory, synchronization, kernels, compilation, numerics, and
communication are shared. Runtime policy and qualification vary by workload.

Training repeatedly runs forward and backward graphs, retains activations or
recomputes them, updates optimizer state, and synchronizes gradients. Online
inference loads a relatively stable model and serves requests with variable prompt
and output lengths under latency and capacity limits. Offline inference values
throughput and cost over per-request latency. Media pipelines decode compressed
streams, transform frames, run vision or multimodal models, and may encode results.

Each workload requires a distinct set of product decisions about state, scheduling,
latency, throughput, and quality.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-domain-engines.svg" alt="A shared accelerator platform branching into training, online inference, offline inference, and media pipelines, each with different state, scheduling, quality, and latency requirements.">
  <figcaption>All four paths use the shared lower stack. Each has its own runtime requirements.</figcaption>
</figure>

## Training state and numerical qualification

Training state includes parameters, gradients, optimizer state, RNG state,
data-loader position, learning-rate schedules, and distributed layout. The runtime
must support forward and backward operators, mixed precision, gradient scaling,
recomputation, collective overlap, and checkpoints that can resume without changing
the experiment.

Training qualification measures throughput per step or per token together with
these workload properties:

- Does the model converge at the expected rate and quality?
- Is memory stable across long runs?
- Can checkpoints restore across the supported topology?
- Do stragglers, thermal changes, or link errors destabilize the job?
- Can profiler traces connect framework operations to kernels and collectives?

Runs that continue for days or weeks amplify small numerical errors and expose rare
reliability events.

## Online inference scheduling

An inference server executes forward graphs within a request-processing runtime. It
accepts requests, tokenizes and validates them, admits work against memory, builds
prefill batches, runs continuous decode batches, manages KV pages, samples tokens,
streams output, handles cancellation, and exposes metrics and health.

The two transformer phases stress hardware differently. Prefill processes many
prompt tokens and often has enough matrix work to be compute-bound. Decode advances
one token per sequence and repeatedly reads weights and KV state, making memory
bandwidth, batching, and scheduler overhead central.

Serving runtime requirements include:

- Paged KV allocation, reclamation, and prefix reuse.
- Continuous batching across requests at different positions.
- Chunked prefill and admission control.
- Quantized weight and KV formats.
- Structured output, sampling, and tokenizer correctness.
- Backpressure and cancellation that release distributed state.
- Time-to-first-token, inter-token latency, throughput, and tail metrics.
- Model loading, compilation, warming, draining, and rollback.

The service-level objective determines the scheduler. Offline throughput workloads
can tolerate long queues and large batches. Interactive services require short
queues and bounded tail latency.

## Offline inference throughput and durability

Batch inference has known or discoverable input sets, relaxed streaming needs, and
more freedom to sort, bucket, and batch by shape. It can amortize compilation and
model loading, use large batches, and checkpoint progress through the dataset.

Batch-inference qualification measures sustained utilization, storage and input
pipeline throughput, output durability, retry semantics, and cost per item. Online
token-latency benchmarks omit these properties.

## Dedicated media engines

Video codecs such as H.264, HEVC, VP9, or AV1 involve entropy coding, motion
compensation, transforms, filtering, color formats, and reference-frame state.
Dedicated decode and encode blocks can perform much of this work independently of
general compute units. NVIDIA's NVDEC documentation, for example, describes a
decoder that runs separately from the graphics and compute engine and produces
frames in device memory.

A media inference pipeline can use the following stages:

```text
compressed stream
  -> demux and decode
  -> YUV surface
  -> crop, scale, color conversion
  -> tensor layout and normalization
  -> vision or multimodal model
  -> overlay, transcode, or stored result
```

Each boundary may require a copy, format conversion, synchronization point, or
ownership transfer. Media and framework teams need interoperable memory handles,
surface metadata, stream or fence integration, and lifetime rules. A zero-copy path
requires the downstream kernel to consume the media engine's output format and
layout directly.

Codec support is also a capability matrix: generation, profile, level, bit depth,
chroma format, resolution, number of concurrent streams, and encode features. A
generic “AV1 supported” label omits the combinations needed for qualification.

## Multi-engine scheduling

A device may run compute, copies, networking, decode, and encode concurrently.
These engines share memory bandwidth, caches, power, thermal headroom, and sometimes
command infrastructure. Shared-package contention can reduce media-plus-inference
throughput before any engine reports full utilization.

The runtime and profiler need a common timeline. Scheduling should account for
shared bottlenecks and priority inversion. Service isolation may require separate
quotas for media sessions, memory, copy bandwidth, and compute partitions because a
single percentage of “GPU utilization” omits those shared-resource limits.

## APIs for domain runtimes

Framework tensor operators suit many stateless computations. Stateful codec
sessions, network collectives, and serving schedulers require domain APIs that
preserve their state and control models while interoperating with framework memory
and streams.

The API boundary must address two common integration failures:

1. Flattening a stateful engine into awkward stateless tensor calls.
2. Hiding tensors and synchronization inside an opaque domain runtime, which
   prevents participation in compilation, profiling, and memory planning.

Typed handles, importable memory, explicit fences, capability queries, and trace
correlation provide this interoperability across layers.

## Workload capability matrix

The advertised product scope determines which training and inference capabilities
the platform supports:

| Capability | Training platform | Online inference | Offline inference | Media plus AI |
|---|---|---|---|---|
| Backward and optimizer | required | usually absent | usually absent | model-dependent |
| Low single-request latency | secondary | central | secondary | pipeline-dependent |
| Continuous batching and KV | no | central for LLMs | useful | model-dependent |
| Long-run numerical convergence | central | no | no | no |
| Dataset and storage throughput | important | moderate | central | central |
| Fixed-function media interop | optional | workload-dependent | workload-dependent | central |
| Distributed collectives | gradient and sharding heavy | model and replica dependent | throughput dependent | pipeline dependent |

A product may cover several columns. Each qualification result must identify the
represented column and workload shape.

---

*Previous: [Scale-Up and Scale-Out](./08-distributed-systems.md). Next: [Qualification and Release](./10-productization.md). [Series index](./accelerator-support.md).*

Sources: [NVIDIA Video Codec SDK](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.1/index.html); [NVDEC programming guide](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvdec-video-decoder-api-prog-guide/index.html); [PyTorch FSDP2](https://docs.pytorch.org/docs/stable/distributed.fsdp.fully_shard.html); [PyTorch Distributed Checkpoint](https://docs.pytorch.org/docs/stable/distributed.checkpoint.html); [MAX serving documentation](https://docs.modular.com/max/serve/).
