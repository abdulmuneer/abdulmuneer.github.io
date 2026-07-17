---
title: "Part 10 - Qualification and Release"
header:
  overlay_image: /assets/images/accelerator/diagram-qualification-gates.svg
  overlay_filter: 0.54
  teaser: /assets/images/accelerator/diagram-qualification-gates.svg
sidebar:
  nav: "accelerator"
---

*Part 10 of [Building Software Support for a New AI Accelerator](./accelerator-support.md).
A product release defines supported hardware and software combinations, backs them
with tests and diagnostics, and routes field failures into software and hardware
changes.*

## End-to-end bring-up

If driver, runtime, framework, kernel, compiler, and packaging teams work
independently for too long, integration failures surface late. An early
end-to-end path exercises their shared contracts:

```text
one supported host
  -> one device and runtime diagnostic
  -> allocate and copy one tensor
  -> execute and profile one kernel
  -> run one eager framework subgraph
  -> compile the same subgraph
  -> compare it with a reference
  -> package and repeat on a clean machine
```

The initial path gives driver, runtime, framework, kernel, compiler, profiler,
packaging, and validation teams one shared artifact and a common failure path.
Coverage and performance then expand on the same integration architecture.

<figure class="align-center">
  <img src="/assets/images/accelerator/diagram-qualification-gates.svg" alt="A gated path from simulator and runtime bring-up through tensor semantics, eager models, compiled models, distributed workloads, performance qualification, release, field telemetry, and feedback to hardware and software design.">
  <figcaption>Qualification gates connect bring-up, release evidence, field telemetry, and changes at the responsible layer.</figcaption>
</figure>

## Qualification gates

**Gate 0: hardware and runtime health.** Device identity, firmware, memory, queues,
events, telemetry, reset, and diagnostics pass on every supported configuration.

**Gate 1: tensor semantics.** Storage, views, copies, factories, RNG,
serialization, streams, and errors match the framework contract.

**Gate 2: eager workload coverage.** Declared models and subgraphs run without
unintended host fallback and pass numerical comparison.

**Gate 3: compiled coverage.** Capture, dynamic shapes, metadata, decompositions,
code generation, cache behavior, and eager parity pass.

**Gate 4: domain qualification.** Training convergence, inference service behavior,
media interoperability, or other promised products pass their own workload gates.

**Gate 5: distributed qualification.** Collectives, framework sharding, topology,
checkpoint, long runs, and injected faults pass at supported scales.

**Gate 6: performance and power.** Representative workload distributions meet
targets without quality loss, hidden fallback, or thermal instability.

**Gate 7: release readiness.** Packages, containers, installation, upgrades,
rollback, ecosystem qualification, documentation, security review, and support
diagnostics work on clean systems.

The gates define the evidence required for a published support claim. Experimental
builds can use looser criteria.

## Cross-layer regression suite

The regression suite should retain small, named reproducers for contracts across
layers:

- ISA and memory-model edge cases.
- Allocation, stream, event, and fault behavior.
- Tensor storage, aliasing, and dtype semantics.
- Operator references and gradients.
- Compiler graphs, dynamic shapes, and cache invalidation.
- Collective ordering, topology, and failure.
- Domain state such as KV pages, optimizer checkpoints, or codec surfaces.

Every field failure caused by an untested contract should produce the smallest
reproducer that still fails for the same reason. Add the reproducer as a permanent
test at the lowest applicable layer and, when warranted, as an end-to-end regression.

## Upstream operator test coverage

Device-specific contract tests and upstream framework operator suites cover
separate requirements. PyTorch uses `OpInfo` records to drive broad suites from
operator metadata and sample inputs. Those suites generate combinations of
references, dtypes, devices, errors, gradients, and other behaviors from this
metadata.

`OpInfo` lives in PyTorch's internal test infrastructure. Its Python packaging lacks
a stable backend API contract. Accelerator qualification should run the upstream
operator suites against a pinned PyTorch revision and retain a record that states:

- The upstream revision, selected suites, operators, dtypes, and sample set.
- Passes through native, composite, and compiled paths, reported separately.
- Expected failures and skips, each with an owner, reason, issue, and review date.
- Device-specific samples that cover layouts, limits, or errors absent upstream.
- Reproducers for the first failing sample, including seed and fallback state.

Report every pass percentage with its denominator. Every skip needs an owner,
reason, issue, and review date. Review dates keep old skips from carrying into later
hardware generations without re-evaluation. Upstream coverage and the local
support matrix should reconcile into the same release claim.

## Performance qualification matrix

The performance matrix should cover workload families, shapes, dtypes, batch or
concurrency, sequence or image sizes, topology, power modes, and cold versus steady
state.

Results need attribution. If a model regresses, the system should separate:

- Host and input pipeline.
- Compilation and cache lookup.
- Guard failures, recompilation, and artifact-cache hits or misses.
- Allocation and transfers.
- Kernel execution and selected algorithms.
- Library dispatch, descriptor setup, heuristic search, and tuning.
- Communication and exposed wait.
- Synchronization and framework overhead.
- Domain scheduling, such as KV admission or media queues.

Assign regression ownership from the attribution. Host input stalls belong to the
data path, graph breaks belong to framework or compiler integration, and slow
kernels belong to the relevant kernel or library implementation.

Steady-state averages omit recompilation of common request shapes and artifact-cache
misses after worker restart. Qualification should report guard failure,
recompilation, and cache-hit rates over the production shape distribution. For
small operations, report cold and warm library dispatch, descriptor and handle
cache hits, tuning time, and kernel time separately.

## Supported compatibility matrix

A release combines hardware stepping, firmware, kernel driver, user runtime,
compiler, libraries, framework package, Python, operating system, and domain
software. Publish and test an explicit subset of this full cross-product.

Publish a matrix that identifies:

- Supported and tested combinations.
- Minimum and maximum compatible versions where known.
- Forward and backward compatibility rules.
- Which component owns firmware and driver updates.
- Cache and checkpoint compatibility.
- Deprecation windows and migration tools.
- Security-update policy.

Out-of-tree framework extensions also face C++ ABI churn. Prefer stable registration
interfaces where available, minimize dependency on private internals, and test
against upcoming framework releases before users do. PyTorch now documents a stable
C++ API for a constrained set of production extension use cases; code outside that
surface still needs a rebuild and compatibility plan.

## Ecosystem release qualification

Users commonly access PyTorch accelerator support through model libraries, training
stacks, serving engines, checkpoint formats, quantization packages, and custom
extensions. These projects change on independent schedules and exercise different
extension points. Qualify each integration separately from the core operator suite.

A release matrix can use projects such as these as qualification workloads:

| Surface | Representative integration | Evidence to retain |
|---|---|---|
| Model APIs | Hugging Face Transformers | representative architectures; `from_pretrained`, generation, training, save and reload; eager and compiled paths |
| Distributed training | TorchTitan, DDP, FSDP2 | single-node and multi-node startup; convergence; parallel layouts; checkpoint and restart |
| Serving | vLLM and SGLang | platform discovery; model loading; KV management; continuous batching; cancellation; distributed serving; tail latency |
| Quantization | torchao | tensor subclasses; packed layouts; conversion; kernels; compilation; serialization; quality checks |
| Checkpoints | PyTorch state, Distributed Checkpoint, Safetensors | CPU staging and direct placement; memory mapping where used; sharded load; dtype and layout preservation |
| Extensions | FlashAttention and representative C++ or Triton extensions | build, import, device dispatch, autograd, `torch.compile`, error behavior, and ABI compatibility |
| Profiling | PyTorch and device tools | operator, graph, kernel, allocation, collective, and hardware-counter correlation |

For each representative project, the qualification artifact must pin its version or
commit, model, configuration, and expected result. A failing row can then be
attributed to the accelerator, framework, integration project, or an unsupported
combination.

## Package and installation qualification

Binary distribution adds another compatibility boundary. A wheel tag identifies
Python, ABI, operating-system, and architecture compatibility. Driver, firmware,
runtime, and optional kernel-package compatibility require separate qualification.
Wheel qualification should cover every promised Python version and platform tag,
isolated installation and upgrade, and the ownership of bundled and host shared
libraries.

Clean-machine qualification must verify installation and runtime behavior:

1. Each wheel installs on its declared Python, OS, and architecture matrix.
2. The package selects compatible driver and device capabilities.
3. Shared libraries resolve without accidental development paths or hidden
   build-tree paths.
4. Bundled libraries, external runtime dependencies, and loader search paths match policy.
5. Kernel and compiler caches use writable, bounded locations.
6. Containers expose devices with the intended permissions.
7. Diagnostics capture versions without leaking secrets.
8. Uninstall, upgrade, and rollback leave a coherent stack.

Reproducible builds, signed artifacts, dependency inventories, and provenance
reduce both support cost and supply-chain risk.

## Production observability

A production trace needs identities that cross layers: request or training step,
graph, operator, generated kernel, stream, allocation, collective, rank, device,
link, and node. Hardware counters and firmware events should correlate with the
same timeline as framework and compiler events.

Metrics need diagnostic value. A single accelerator-utilization metric conflates
useful matrix work, spin loops, memory stalls, communication kernels, and other
tenants. Pair utilization with achieved bandwidth, instruction class, queue delay,
memory pressure, clocks, power, temperature, errors, and workload progress.

Support bundles should be bounded and reviewable. They need exact builds,
capabilities, recent errors, relevant traces, and topology without collecting user
models or data by default.

## Shared engineering artifacts

Teams should exchange versioned, executable artifacts:

- Machine and runtime specifications.
- Simulator and silicon test vectors.
- Operator and dtype support matrices.
- Compiler legality and cost-model tests.
- Kernel performance envelopes.
- Numerical tolerance records.
- Distributed topology and failure tests.
- Release compatibility manifests.
- Field incident reproducers and decision records.

Architecture reviews should ask which artifact proves the claim and which team can
change the constraint. Component status reports must also identify the end-to-end
product qualification state.

## Production evidence in architecture decisions

After the first chip ships, field measurements reveal missing counters, expensive
synchronization, weak atomics, poor tile shapes, insufficient local memory, awkward
low-precision formats, topology bottlenecks, and recovery gaps. These findings
should enter the next architecture cycle with measured frequency and cost.

Route findings to hardware, firmware, compiler strategy, libraries, or product
scope according to measured frequency and cost. Recurring software workarounds
should become explicit architecture requirements or documented product constraints.

## Release criteria for a supported accelerator

A supported accelerator requires a maintained system with the following
properties:

- User-visible semantics are declared.
- Hardware capabilities and limits are queryable.
- Native execution, decomposition, and fallback are distinguishable.
- Compiled and eager results are qualified.
- Numerical modes are explicit.
- Distributed and domain behavior match the advertised product.
- Performance includes the complete workload path.
- Failures retain cause and recovery scope.
- Packages and compatibility survive ordinary upgrades.
- Evidence from production improves the next release and the next machine.

A PyTorch support claim requires evidence for each obligation.

---

*Previous: [Training, Inference, and Media Engines](./09-domain-engines.md). Next: [Framework Boundaries and Vendor Stacks](./11-pytorch-jax-max-vendor-stacks.md). [Series index](./accelerator-support.md).*

Sources: [PyTorch accelerator integration](https://docs.pytorch.org/docs/stable/accelerator/index.html); [PyTorch profiler integration](https://docs.pytorch.org/docs/main/accelerator/profiler.html); [PyTorch C++ extension documentation](https://docs.pytorch.org/docs/stable/cpp_extension.html); [PyTorch Stable C++ API](https://docs.pytorch.org/cppdocs/api/stable/index.html); [PyTorch OpInfo source](https://github.com/pytorch/pytorch/tree/main/torch/testing/_internal/opinfo); [PyTorch operator tests](https://github.com/pytorch/pytorch/blob/main/test/test_ops.py); [TorchTitan](https://github.com/pytorch/torchtitan); [Transformers installation](https://huggingface.co/docs/transformers/main/en/installation); [vLLM installation and hardware plugins](https://docs.vllm.ai/en/stable/getting_started/installation/); [SGLang installation](https://docs.sglang.io/docs/get-started/install); [torchao documentation](https://docs.pytorch.org/ao/stable/index.html); [Safetensors documentation](https://huggingface.co/docs/safetensors/main/index); [FlashAttention](https://github.com/Dao-AILab/flash-attention); [Python wheel specification](https://packaging.python.org/en/latest/specifications/binary-distribution-format/); [MLIR pass crash reproducers](https://mlir.llvm.org/docs/PassManagement/#crash-and-failure-reproduction); [PyTorch reproducibility](https://docs.pytorch.org/docs/stable/notes/randomness.html).
