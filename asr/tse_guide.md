---
title: "Part 0 - Target Speaker Following for ASR"
permalink: /asr/target-speaker-following/
header:
  overlay_image: /assets/images/hero-asr.svg
  overlay_filter: 0.55
  teaser: /assets/images/hero-asr.svg
sidebar:
  nav: "asr"
---

*Part 0 of the ASR systems series. The problem is not "make ASR better at noisy audio." The problem is narrower and harder: make ASR follow one speaker when other people are also talking.*

Most ASR systems are happiest when the input contains one clear voice. That assumption holds in studio samples and clean demos. It breaks in meeting rooms, call centers, voice assistants, field recordings, and any live conversation where the person you care about is not the only talker in the waveform.

Once two speakers overlap, the recognizer is being asked to solve two problems at once:

1. Recognize speech.
2. Decide whose speech should count.

Those are different jobs. A recognizer can become more robust to noise, reverb, accents, codecs, and microphones, but it still does not know which competing speaker is the one the product meant to follow. That is where target speaker following belongs. It is the front-end policy and signal-processing layer that decides what audio reaches ASR.

The useful mental model is simple:

> Do not ask ASR to solve speaker selection. If the target is clean, pass the original audio. If the target is mixed but recoverable, extract the target first. If there is no usable target signal, skip the recognizer and say why.

This post is a practical architecture for doing that without tying the design to one proprietary model, dataset, or ASR stack.

## The Three Routes

Target speaker following is a routing problem before it is a modeling problem. Every speech window should land in one of three routes:

| Route | Meaning | ASR input |
|---|---|---|
| `PASS_THROUGH` | The desired speaker is clean and dominant. | The original speech window. |
| `EXTRACT` | The desired speaker is present, overlapped, and recoverable. | A target-speaker waveform produced by the extraction model. |
| `CUTOFF` | There is no usable target-speaker signal. | No ASR call. Emit a terminal skip or failure event. |

That contract matters because it keeps the system honest. Separation is not always helpful. On clean target speech, extraction can introduce artifacts and make recognition worse. On unrecoverable overlap, ASR will happily hallucinate a transcript from the wrong person if you feed it garbage. The router's job is to protect the recognizer from both errors.

The first production milestone should not be "run a separator in front of everything." It should be "make the route decision observable." Once you can measure pass-through, extraction, and cutoff separately, you can tune the system without hiding failures inside word error rate.

## Keep TSE Out Of The Default ASR Path

A practical deployment keeps the ASR service and the target speaker extraction service separate:

| Layer | Responsibility | Typical placement |
|---|---|---|
| API/session layer | Chunk ordering, session state, route selection, client events. | Web or API process. |
| VAD layer | Convert audio into speech windows. | API process or lightweight helper. |
| Cheap evidence layer | Energy, duration, coarse dominance, optional speaker embedding. | API process. |
| TSE layer | Speaker embeddings, overlap detection, extraction, recoverability. | Separate CPU/GPU service. |
| ASR layer | Transcribe admitted raw or extracted windows. | ASR service. |

This boundary is not only about neat architecture. Heavy separation dependencies have their own model load time, GPU memory behavior, failure modes, and scale profile. If every clean single-speaker request has to carry that weight, the common path pays for the rare path.

Keep the API/session layer in charge of policy. Let the TSE service return evidence and, when requested, an extracted waveform. That keeps state, hysteresis, timeouts, degradation policy, and user-visible events in one place.

## The Lifecycle

The live path should operate on VAD speech windows, not arbitrary upload chunks. A chunk might contain silence, half a word, two turns, or an overlap boundary. The routing unit needs to be closer to speech.

<p style="text-align:center"><img class="brand-logo" src="/assets/images/asr-lifecycle.svg" alt="Target speaker following lifecycle" style="width:980px;max-width:100%"></p>

There are two details here that are easy to skip and painful to add later.

First, each input chunk needs one terminal event even when nothing is transcribed. Streaming clients should not have to guess whether silence, target loss, TSE timeout, or server failure caused a missing transcript.

Second, if session state lives in memory, the session needs affinity. Every chunk for that session must reach the same worker, or the target profile and lock state will split across processes. If you cannot guarantee affinity, externalize the profile and state storage deliberately.

## Acquiring The Target

There are two common ways to decide who the target speaker is:

| Mode | How the target is chosen | Good fit |
|---|---|---|
| Fixed enrollment | A known target speaker sample is provided. | Meetings, diarized workflows, assistants tied to a known user. |
| Online dominant speaker | The system follows the first or current dominant speaker and can re-latch. | Field audio, turn-taking, no enrollment available. |

Fixed enrollment is simpler to reason about because identity starts outside the session. Online acquisition is more delicate because the system must decide when it has seen enough clean speech to lock onto someone.

Do not lock on a single short frame. Require consecutive clean dominant windows. Update the profile only on high-confidence target speech. Do not update it during overlap.

The most important trick in online acquisition is to compare new windows to the accumulating candidate centroid, not only to the previous window. Short-window speaker embeddings are noisy. Same-speaker pairwise scores can overlap with different-speaker scores, especially with short windows, similar voices, or channel changes. A running centroid of accepted windows is usually more stable.

That gives you two separate thresholds:

| Threshold | Purpose |
|---|---|
| Acquire similarity | Loose enough to let a clean candidate profile grow. |
| Switch similarity | Strict enough to justify abandoning an existing lock. |

The acquire threshold should usually be lower than the switch threshold. Reusing the strict switch gate for acquisition often causes the latch to starve: the system keeps seeing the same speaker, but refuses to collect enough evidence to prove it.

## Holding, Losing, And Switching

Once the target is acquired, the router should behave like a small state machine:

| State | Meaning |
|---|---|
| `COLD` | No target profile yet. |
| `ACQUIRING` | Candidate speaker observed; waiting for confirmation. |
| `LOCKED` | Target profile active; route each speech window. |
| `GRACE` | Target briefly absent; keep the profile for a limited time. |
| `SWITCHING` | A new dominant speaker is persistent; prepare to re-latch. |
| `LOST` | Speech exists, but no usable target signal is recoverable. |

Use counters, not single-window decisions. Require several consecutive target windows to acquire, several absent windows before entering grace, and several self-consistent challenger windows before switching. This is standard hysteresis, but it matters more here than in many ASR features because a bad switch does not merely lower confidence. It changes whose words appear in the transcript.

The policy should also distinguish between target absence and unrecoverable target overlap. If another speaker dominates and the target is not present, that is `no_target`. If the target may be present but extraction cannot produce usable speech, that is `unrecoverable_overlap`. Those states deserve different metrics and product behavior.

## What The TSE Service Should Return

On the live path, prefer one call that can analyze and optionally extract:

```text
POST /route
```

For operations and warmup, a minimal service usually also exposes:

```text
GET  /health
POST /warmup
POST /analyze
POST /extract
```

Use binary audio transport rather than base64 JSON. `multipart/mixed`, gRPC bytes, or a similar binary path is a better fit for live audio. Shared object storage is fine for offline batch jobs, but it is usually the wrong tool for low-latency streaming.

A route response should include enough evidence for the API layer to make and explain the decision:

| Field | Meaning |
|---|---|
| `profile_id` or `dominant_embedding` | Speaker identity evidence. |
| `sim_to_profile` | Similarity to the current target profile. |
| `overlap_probability` | Probability of concurrent speakers. |
| `dominance` | How much speech energy belongs to the strongest speaker. |
| `recoverability` | Confidence that extracted target speech is usable. |
| `model_version` | Reproducibility for analysis and rollback. |
| `latency_ms` | Timing for evidence and extraction. |

The response should not force the caller to trust the model blindly. It should expose the scores that make the route auditable.

## Public Building Blocks

The exact stack depends on latency, licensing, domain fit, and hardware. Reasonable public starting points include:

| Need | Candidate tools |
|---|---|
| VAD | Silero VAD, WebRTC VAD, FunASR FSMN-VAD, pyannote segmentation. |
| Speaker embeddings | SpeechBrain ECAPA-TDNN, Resemblyzer, NVIDIA NeMo speaker models, WavLM-based encoders. |
| Overlap detection | pyannote overlapped speech detection, segmentation heads, custom binary classifiers. |
| Blind separation prototype | SpeechBrain SepFormer, Asteroid Conv-TasNet/DPRNN/SepFormer, ESPnet-SE. |
| Target-conditioned extraction | VoiceFilter-style models, SpeakerBeam, WeSep, ESPnet-SE target-speaker recipes, NeMo separation pipelines where appropriate. |
| Audio I/O | FFmpeg, torchaudio, soundfile, librosa for offline analysis. |
| Serving | FastAPI, gRPC, Triton Inference Server, TorchServe, Ray Serve, Kubernetes workers. |
| Metrics | jiwer for WER/CER, pyannote.metrics, Prometheus, OpenTelemetry. |

Blind separation is useful for validating plumbing, but target-conditioned extraction is usually the production direction. Blind separation still has to choose which separated stream belongs to the target. That stream-selection step is fragile under similar voices, fast turn-taking, and off-domain audio.

Measure extracted-input WER against raw-mixture WER on held-out mixtures before enabling route 2. A raw mixture is not a weak baseline. It is the bar extraction must clear.

## The Knobs That Matter

Every threshold is local to your embedding model, microphone domain, language, VAD windowing, extraction model, and latency budget. Treat defaults as seeds, not truths.

For VAD and windowing, tune:

| Knob | Tradeoff |
|---|---|
| VAD speech threshold | Lower catches weak speech but creates more false speech windows. |
| Min speech duration | Longer stabilizes embeddings but increases latency. |
| Padding before and after speech | Protects word boundaries but may include interferers. |
| Max window duration | Longer helps context; shorter lowers TSE and ASR latency. |
| Separate analysis and ASR windows | Longer analysis can improve identity while keeping ASR chunks small. |

For identity, tune:

| Knob | Meaning |
|---|---|
| Embedding backend | Speaker encoder family and version. |
| Embedding normalization | L2, score normalization, cohort normalization, or none. |
| Min speech for embedding | Minimum speech before a profile is trusted. |
| Clean-pass similarity | Similarity required to pass raw audio as target. |
| Extraction-attempt similarity | Looser similarity that says extraction is worth trying. |

The extraction-attempt threshold should usually be lower than the clean-pass threshold. Route 2 should prioritize recall of salvageable target speech, then let recoverability decide whether the extracted signal is usable.

For overlap and dominance, tune:

| Knob | Meaning |
|---|---|
| Overlap threshold | Escalates likely mixed speech to TSE. |
| Dominance threshold | Decides whether one speaker is clean enough for raw ASR. |
| Energy floor | Prevents scoring background noise as speech. |
| Target activity floor | Avoids extracting when the target is probably absent. |

One subtle but important point: overlapped-speech detectors flag concurrent talkers. They do not detect environmental noise in general. A single target speaker plus music, fan noise, or a siren is not automatically a target-speaker problem. There is no wrong speaker to suppress. That case belongs mostly to ASR robustness and denoising, while target speaker following should focus on competing-speaker leakage.

For recoverability, tune:

| Knob | Meaning |
|---|---|
| Recoverability threshold | Minimum extraction quality for route 2. |
| Target SNR estimate | Expected target-to-interferer ratio after extraction. |
| Post-extraction speaker similarity | Confirms the output still matches the target. |
| Post-extraction VAD coverage | Confirms the output contains speech, not artifacts. |

Calibrate recoverability against actual post-extraction ASR quality. A confidence score is only useful if it predicts when extraction improves recognition.

## Tune In Dependency Order

The tuning order matters because upstream changes invalidate downstream thresholds:

1. Freeze VAD and windowing enough to produce stable speech windows.
2. Choose and freeze the speaker embedding model and score normalization.
3. Tune identity, overlap, and dominance thresholds.
4. Tune the acquisition, release, grace, and switch counters.
5. Freeze the extraction model.
6. Calibrate recoverability against post-extraction ASR quality.
7. Set latency budgets and failure policies under load.

Changing the speaker encoder invalidates identity thresholds. Changing the extractor invalidates recoverability. Changing VAD windowing can invalidate both.

## Evaluate The Router, Not Only The Transcript

Do not tune target speaker following on clean single-speaker audio alone. Build evaluation slices that expose the failure modes:

| Slice | What it measures |
|---|---|
| Clean target | Route 1 quality and no regression on normal ASR. |
| Target plus one interferer | Route 2 quality across target/interferer ratios. |
| Non-target only | False accept and speaker leakage risk. |
| Turn-taking | Switch latency and false switches. |
| Overlap chatter | Unrecoverable speech detection. |
| Far-field, reverb, noise | Robustness under channel degradation. |
| Session starts | Acquisition latency and wrong-lock rate. |

Track both recognition quality and routing quality:

| Metric | Why it matters |
|---|---|
| Target-speaker WER/CER | Measures whether the desired speaker is recognized. |
| Raw-ASR vs extracted-ASR WER | Proves extraction helps where it is used. |
| Clean route-1 WER | Guards against degrading clean audio. |
| Route confusion matrix | Shows wrong pass, extract, and cutoff decisions. |
| Non-target false accept rate | Measures interferer leakage into transcripts. |
| Target miss rate | Measures dropped desired speech. |
| Switch latency and false switch rate | Measures latching behavior. |
| Failure precision/recall | Ensures unrecoverable events are meaningful. |
| p50/p95/p99 latency per route | Keeps live UX within budget. |
| TSE hit rate | Drives GPU capacity planning. |

Promotion should require improvement over both raw ASR and gate-only routing on overlapped audio, with no regression on clean single-speaker audio.

## Observability And Privacy

Emit aggregate metadata, not sensitive payloads:

- route selected: pass-through, extract, or cutoff;
- router state: cold, acquiring, locked, grace, switching, or lost;
- evidence tier used: cheap local evidence or TSE service;
- rounded overlap, dominance, similarity, and recoverability scores;
- degradation flag and reason;
- TSE latency and ASR latency;
- skip reason for cutoff windows.

Useful skip reasons include:

| Reason | Meaning |
|---|---|
| `no_speech` | VAD found no speech in the chunk. |
| `no_target` | Target profile is not active in this window. |
| `non_target_dominant` | Another speaker dominates under the current lock. |
| `unrecoverable_overlap` | Target may be present, but extraction quality is too low. |
| `failed_to_detect_speech` | Sustained speech exists, but no recoverable target signal remains. |

Speaker embeddings, enrollment samples, and extracted target waveforms are biometric-derived data. Keep profile lifetime session-scoped unless persistence is explicitly required. Use opaque profile ids across service boundaries. Encrypt service-to-service traffic outside a trusted network. Do not log raw audio, extracted audio, embeddings, enrollment samples, or request payloads.

The privacy rule is also an engineering rule: when a production incident needs investigating, logs should explain routing decisions without containing the user's voice.

## Rollout Plan

Ship target speaker following behind feature flags:

1. Land VAD/windowing refactors with TSE disabled.
2. Add session state and route metadata without changing ASR input.
3. Run shadow mode: compute routes but still transcribe baseline audio.
4. Enable pass-through and cutoff for internal sessions.
5. Add extraction behind a separate flag.
6. Canary on overlap-heavy traffic.
7. Expand only after quality, latency, failure, and privacy gates pass.

A gate-only mode, using `PASS_THROUGH` and `CUTOFF` without extraction, is useful for staged rollout and outages. It is not a complete solution to overlapped target speech, but it gives you a safe control plane before you add a heavier model to the live path.

## The Failure Modes To Expect

| Failure | Mitigation |
|---|---|
| Extraction hurts clean speech | Prefer pass-through for clean dominant windows. |
| Latch never locks | Gate acquisition against the candidate centroid with a looser threshold than switching. |
| Wrong speaker becomes the target | Require acquisition and switch hysteresis. |
| Interferer text leaks into transcript | Raise clean-pass threshold and bias uncertainty toward TSE. |
| Target is dropped too often | Lower extraction-attempt threshold and retune recoverability. |
| Route 2 is too slow | Use tiered evidence, queue limits, smaller models, batching, or dedicated GPUs. |
| Recoverability score is uncalibrated | Fit it to post-extraction WER on held-out mixtures. |
| Session state splits across workers | Use sticky routing or externalize profile/state storage. |
| Logs leak biometric material | Add tests or grep guards for vectors, audio blobs, and request payloads. |

## The Minimal Shape

The smallest version worth building has these pieces:

- TSE feature flag off by default.
- Canonical audio decode path.
- Shared VAD windowing.
- Session-affine worker or external state store.
- Speaker profile lifecycle: acquire, lock, grace, switch, lost, cleanup.
- TSE service with health, warmup, analyze, extract, and route endpoints.
- Binary audio transport and timeout-safe client.
- Three routes: pass-through, extract, cutoff.
- Explicit failure and degradation policy.
- Additive client metadata.
- No logging of audio, embeddings, or profile vectors.
- Offline tuning harness with held-out overlap, non-target, and turn-taking slices.
- Latency and capacity benchmark.
- Shadow-mode rollout before production routing.

The architecture is less about one extractor and more about keeping responsibilities separate. ASR recognizes admitted speech. TSE supplies identity, overlap, extraction, and recoverability evidence. The session router decides which route is safe, emits the event clients need, and records enough telemetry to improve the decision later.

That is target speaker following as a system: a measurable front end that lets ASR stay focused on recognition while the product stays honest about whose voice it is transcribing.

---

*Next: more ASR system notes to come. [Series index](./asr.md).*
