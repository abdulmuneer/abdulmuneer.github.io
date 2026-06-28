---
title: "Picking a Voice Gate: Tuned Silero VAD vs FunASR FSMN-VAD"
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-ember.svg
---

*Field notes from tuning a voice-activity detector for a speech-to-text pipeline,
then putting it head-to-head with a second VAD on a held-out benchmark of 3,000
clips. Less "release notes," more "here is what the numbers actually said when I
stopped guessing."*

## Why a VAD sits in front of ASR at all

A voice-activity detector (VAD) is the bouncer at the door of a speech-to-text
system. Its one job is to decide, per chunk of audio, *is anyone speaking?* —
and to keep silence, fan noise, music, and street sound from ever reaching the
transcription model.

That gate matters more than it looks. Modern ASR models are eager to please:
hand them a few seconds of pure noise and they will frequently *hallucinate* a
plausible-sounding sentence rather than return nothing. A good VAD is the
cheapest, most reliable defense against that failure mode. So the question I
cared about wasn't only "does it find speech" — it was "how aggressively does it
refuse to pass through things that aren't speech."

I had two candidates:

- **[Silero VAD](https://github.com/snakers4/silero-vad)** — a small, fast,
  widely used neural VAD with a tunable post-processing layer (thresholds,
  minimum durations, padding).
- **[FunASR's FSMN-VAD](https://huggingface.co/funasr/fsmn-vad)** — the VAD that
  ships with the FunASR toolkit, run here on CPU with its default behavior.

This post is the write-up of (a) tuning Silero's post-processing parameters
offline, and (b) comparing tuned Silero against FSMN-VAD on a held-out set the
tuning never saw.

## The short version

- Tuning Silero's post-processing was worth it. On the held-out set, the
  false-positive rate on non-speech audio dropped from the upstream Silero
  default of `0.034` to `0.007` — a **79% relative reduction** — while speech
  recall barely moved, from `0.998` to `0.997`.
- FSMN-VAD was **~2.2× faster** in steady-state CPU batch mode and hit *perfect*
  speech recall (`1.0000`, zero missed speech clips). But it was far more
  permissive on non-speech: it let through `237/1000` noise clips
  (`FPR=0.237`) versus tuned Silero's `7/1000` (`FPR=0.007`).
- There is no universal winner. The right answer depends on the use case:
  a strict gate for live audio wants tuned Silero; a high-recall speech-window
  finder for offline file transcription can prefer FSMN-VAD.

| Use case | VAD choice | Why |
|---|---|---|
| Live / streaming mic input | **Tuned Silero VAD** | This path must aggressively keep non-speech out of ASR. Tuned Silero accepted only `7/1000` non-speech clips while holding speech recall at `0.997`. |
| Uploaded files / offline batch | **FSMN-VAD (CPU)** | You can't ask a user to re-record a file they already uploaded, so never dropping real speech is paramount. FSMN-VAD had `1.0000` recall and zero speech false-negatives, making it a strong high-recall speech-window finder. |

The one thing I would *not* do is use default FSMN-VAD as a strict gate for live
audio: at `FPR=0.237` it admits roughly **34× more** non-speech than tuned
Silero.

## The benchmark setup

Everything below is a **file-level acceptance benchmark**: each clip is labeled
speech or non-speech, each VAD either accepts it (finds speech) or rejects it,
and I score the confusion matrix. It is deliberately *not* a frame-level
segmentation benchmark — the question is "should this file reach ASR," not "did
we get the exact word boundaries."

Both models ran on CPU, decoding audio locally and resampling to 16 kHz mono. No
ASR server was involved at any point; this isolates VAD behavior from everything
downstream.

### The data

The held-out set is 3,000 clips drawn from public speech and audio-event
corpora, with a small in-house Arabic set mixed into the speech side:

| Category | Count | Duration range (s) | Mean (s) |
|---|---:|---:|---:|
| Arabic speech | 1000 | 1.0 – 43.0 | 4.15 |
| English speech | 1000 | 2.05 – 31.08 | 9.66 |
| Non-speech / noise | 1000 | 0.31 – 34.22 | 6.29 |

Total audio: ~20,096 seconds (about 5.6 hours). Crucially, **the held-out set
shares zero source clips with the tuning set** — every file used to pick Silero's
parameters was excluded here, so the tuned numbers aren't just memorization.

One subtlety worth flagging: babble and crowd-murmur clips are *voice-like* and
should legitimately wake a VAD, so they don't belong in the non-speech negative
class. I excluded that category from the negative set up front rather than
penalizing either model for correctly reacting to human voices.

## Tuning Silero

Silero gives you a neural frame-probability stream and a post-processing layer
that turns those probabilities into speech segments. That layer has knobs, and
defaults that are tuned for general use rather than "guard an ASR model." The
knobs:

- `threshold` / `neg_threshold` — the hysteresis pair for entering/leaving speech
- `min_speech_duration_ms` — discard speech blips shorter than this
- `min_silence_duration_ms` — how long silence must last to end a segment
- `speech_pad_ms` — padding added around detected speech
- `max_speech_duration_s` — cap on a single segment

Rather than hand-tune, I ran an offline search:

1. Decode each clip locally, resample to 16 kHz mono.
2. Run Silero's neural net **once per file** to cache the raw frame
   probabilities — so the search never re-runs the model.
3. Reimplement Silero's threshold/`neg_threshold` hysteresis segmentation over
   those cached probabilities, so candidate parameter sets are cheap to score.
4. Evaluate 360 candidate parameter sets on a stratified train split.
5. Fit an `ExtraTreesRegressor` surrogate over the five post-processing
   parameters.
6. Use the surrogate to rank 5,000 unseen candidate settings, directly evaluate
   the top 80, and pick the best validation candidate across the ~440 settings
   actually scored.

The objective penalized false negatives slightly more than false positives,
while still punishing non-speech acceptance — encoding the asymmetry that
clipping real speech is costly, but letting noise reach ASR is *also* costly
because of hallucinations.

The winning configuration:

```text
threshold              = 0.8
neg_threshold          = 0.65
min_speech_duration_ms = 500
min_silence_duration_ms= 800
speech_pad_ms          = 200
max_speech_duration_s  = 28.0
```

### Did tuning actually help?

Yes, and consistently across every split. Compared to the upstream Silero helper
defaults (`threshold=0.5`, `neg_threshold=0.35`, `min_speech_duration_ms=250`,
`min_silence_duration_ms=100`, `speech_pad_ms=30`):

| Split | Params | Speech recall | Noise FPR |
|---|---|---:|---:|
| Tuning validation | Tuned | 0.9967 | **0.0533** |
| Tuning validation | Upstream default | 0.9950 | 0.1000 |
| Full tuning set | Tuned | 0.9965 | **0.0540** |
| Full tuning set | Upstream default | 0.9970 | 0.0800 |
| Held-out | Tuned | 0.9970 | **0.0070** |
| Held-out | Upstream default | 0.9980 | 0.0340 |

The noise false-positive rate fell on every split: `0.10 → 0.053` on the
validation split, `0.08 → 0.054` on the full tuning set, and `0.034 → 0.007` on
the held-out set — all while speech recall stayed within a thousandth or two.

A nice side effect: because the tuned `speech_pad_ms=200` is far less
boundary-aggressive than Silero's `30 ms` default, the tuned config also
*preserves more of the surrounding speech audio* — fewer clipped word edges
feeding into ASR.

## Tuned Silero vs FSMN-VAD

FSMN-VAD ran on CPU with default post-processing. Here's the head-to-head on the
full 3,000-clip held-out set.

Metric definitions: positive class = "accepted as speech." Recall = speech
clips accepted. Specificity = non-speech clips rejected. FPR = non-speech clips
wrongly accepted. RTF (real-time factor) = processing seconds ÷ audio seconds;
lower is faster.

| Model | Precision | Recall | F1 | Specificity | FPR | FP | FN | RTF |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Tuned Silero VAD | 0.9965 | 0.9970 | 0.9968 | **0.9930** | **0.0070** | 7 | 6 | 0.00668 |
| FunASR FSMN-VAD (CPU) | 0.8941 | **1.0000** | 0.9441 | 0.7630 | 0.2370 | 237 | **0** | **0.00302** |

The trade-off is stark and clean:

- **Silero is the stronger gate.** It missed 6 speech clips out of 2,000 but let
  through only 7 non-speech clips out of 1,000.
- **FSMN-VAD never misses speech.** Zero false negatives across 2,000 speech
  clips — but it accepted 237 non-speech clips.

Breaking the non-speech failures down by source shows where FSMN-VAD struggles —
environmental sound and music, mostly:

| Non-speech source | Count | Silero FP | FSMN FP | Silero FPR | FSMN FPR |
|---|---:|---:|---:|---:|---:|
| ESC-50 (environmental sounds) | 250 | 1 | 90 | 0.004 | 0.360 |
| FSD50K (noise / music) | 250 | 5 | 82 | 0.020 | 0.328 |
| Synthetic noise (TTS-style) | 250 | 0 | 0 | 0.000 | 0.000 |
| Silence / low-level noise | 250 | 1 | 65 | 0.004 | 0.260 |

Both models trivially reject synthetic noise. But on real recorded environmental
sound and music, FSMN-VAD's default post-processing waves through a third of the
clips. On the speech side, both models are near-perfect; Silero's handful of
misses are spread thinly across Arabic and English public-corpus clips.

### Speed and load

FSMN-VAD wins on raw throughput once warm:

- Tuned Silero: ~134 s to process the set, RTF `0.00668`.
- FSMN-VAD: ~61 s, RTF `0.00302` — about **2.2× faster** by process time.

The asymmetry flips on startup cost, though. Silero's cached model load is
`~0.12 s`; FSMN-VAD's is `~8.4 s` warm, and its very first cold run (download +
load) was around 62 s. For a long-lived service that loads once, FSMN-VAD's
steady-state speed is what matters; for short-lived or frequently-restarted
workers, Silero's near-instant load is the friendlier number.

## So which one?

Both. They're good at different jobs, and the cost of each mistake is different
depending on where the audio comes from.

**For live or streaming microphone input**, a false positive is expensive: noise
that slips through becomes a hallucinated transcript that a user or downstream
agent then has to deal with in real time. Here the strict gate wins — **tuned
Silero**, with its `0.007` non-speech FPR.

**For uploaded files and offline batch transcription**, a false *negative* is the
expensive one: you cannot ask someone to re-record a file they already sent, so
silently dropping a stretch of real speech is the worst outcome. Here FSMN-VAD's
perfect recall makes it an attractive high-recall speech-window finder ahead of
the ASR model — you trade some strictness for the guarantee that no real speech
is thrown away.

What I would avoid is treating "the fast one" as a drop-in strict gate for live
audio. FSMN-VAD is genuinely promising — perfect recall, 2× the throughput — but
out of the box it's ~34× more permissive on non-speech, and for a live ASR gate
that permissiveness is exactly the thing you're trying to prevent.

## Caveats and what I'd test next

A few honest limitations:

- This is a **file-level** acceptance benchmark, not frame-level segmentation.
- FSMN-VAD ran with **default** post-processing. Like Silero, it almost certainly
  has headroom under tuning — its raw permissiveness isn't necessarily its
  floor, and a tuned FSMN-VAD comparison is the obvious follow-up.
- Source labels are practical benchmark labels, not exhaustive human acoustic
  annotations.
- Timing includes local audio decode plus inference, not inference alone.

The next experiment I'd run is the offline path end-to-end: take FSMN-VAD as the
high-recall front end, measure how much audio it actually compresses away, and
then check transcript quality and hallucination behavior *after* ASR — because a
VAD's real grade is the quality of the transcripts it lets through, not its
confusion matrix in isolation.

---

*Sources: [Silero VAD](https://github.com/snakers4/silero-vad) ·
[FunASR FSMN-VAD](https://huggingface.co/funasr/fsmn-vad)*
