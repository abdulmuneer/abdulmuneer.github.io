---
title: "Tuning Voice Activity Detection for ASR Gating"
header:
  overlay_image: /assets/images/hero-asr.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-asr.svg
sidebar:
  nav: "asr"
toc: true
---

*VAD post-processing defaults are set for general use, not for gating an ASR
model. This post is about the difference tuning makes, using Silero VAD and
FunASR's FSMN-VAD as examples evaluated on a held-out benchmark.*

## Why the gate matters

A voice-activity detector (VAD) runs in front of an ASR model and decides, per
chunk of audio, whether speech is present. It passes speech through and holds
back silence, noise, and music.

This matters because of how ASR models behave on non-speech input. Given a few
seconds of pure noise, most models emit a plausible sentence rather than nothing.
The VAD is the main defense against that, so the relevant question is not only
whether it detects speech but how reliably it rejects audio that is not speech.

Rejection behavior is controlled by a post-processing layer (thresholds, minimum
durations, padding). Its defaults are set for general-purpose use rather than ASR
gating, and tuning is what adapts them. The two VADs below are examples, not a
recommended shortlist:

- [Silero VAD](https://github.com/snakers4/silero-vad): a small, fast, widely
  used neural VAD with a tunable post-processing layer.
- [FunASR's FSMN-VAD](https://huggingface.co/funasr/fsmn-vad): the VAD that ships
  with the FunASR toolkit, run here on CPU with its default behavior.

## Summary

- Tuning Silero's post-processing sharply reduced false positives on non-speech
  while leaving speech recall effectively unchanged.
- High recall alone does not indicate a good gate. Default FSMN-VAD reached
  near-perfect speech recall and ran faster in steady-state CPU batch mode, but
  let through far more non-speech than tuned Silero.
- The operating point a VAD runs at is set by its post-processing, and defaults
  rarely sit where an ASR gate needs them.

## The benchmark setup

The evaluation is at the level of whole clips rather than frame boundaries. Each
clip is labeled speech or non-speech, each VAD either accepts or rejects it, and
the two are compared. The question being measured is whether a file should reach
ASR, not where the word boundaries are.

Both models ran under the same conditions on CPU. No ASR was involved, which
isolates VAD behavior from everything downstream.

The evaluation set mixes speech and non-speech audio across a few categories, and
is kept separate from any audio used for tuning so the tuned results are not
just memorization. Voice-like material such as babble and crowd murmur is treated
as speech rather than noise, since a VAD reacting to human voices is behaving
correctly.

## Tuning Silero

Silero exposes a neural frame-probability stream and a post-processing layer that
converts those probabilities into speech segments. The parameters:

- `threshold` / `neg_threshold`: the hysteresis pair for entering/leaving speech
- `min_speech_duration_ms`: discard speech blips shorter than this
- `min_silence_duration_ms`: how long silence must last to end a segment
- `speech_pad_ms`: padding added around detected speech
- `max_speech_duration_s`: cap on a single segment

The parameters came from an offline search rather than hand-tuning. The key idea
is that the neural network output only has to be computed once: run the model
per file, cache the frame probabilities, and then sweep the post-processing
parameters over those cached probabilities, which makes evaluating many
candidate settings cheap. Candidates are scored on a held-out split and the best
one is selected.

The scoring objective penalized false negatives slightly more than false
positives while still penalizing non-speech acceptance. This reflects the
asymmetry that clipping real speech is costly and that letting noise reach ASR is
also costly because of hallucinations.

Relative to Silero's upstream helper defaults, the selected configuration moved in
a consistent direction: a higher entry/exit threshold pair, longer minimum speech
and silence durations, and more padding around detected speech. In short, a
stricter, less twitchy gate.

### Effect of tuning

Tuning improved results consistently, including on data held out from the search.
The pattern was the same throughout: non-speech false positives dropped
substantially while speech recall stayed flat.

A side effect: the tuned padding is less boundary-aggressive than Silero's
default, so the tuned configuration preserves more of the surrounding speech audio
and reduces clipped word edges into ASR.

## Tuned vs default: Silero against FSMN-VAD

To show the cost of leaving a VAD untuned, here is tuned Silero against FSMN-VAD
with default post-processing, on the same held-out set.

Metric definitions: positive class = "accepted as speech." Recall = speech clips
accepted. Specificity = non-speech clips rejected. False positives = non-speech
clips wrongly accepted.

| Model | Speech recall | Non-speech rejection | False positives | Throughput (warm) |
|---|---|---|---|---|
| Tuned Silero VAD | Near-ceiling | High | Very low | Slower |
| FunASR FSMN-VAD (default, CPU) | Perfect | Lower | Much higher | Faster |

Tuned Silero is the tighter gate: it missed very few speech clips and let through
very little non-speech. Default FSMN-VAD missed no speech at all but accepted far
more non-speech.

The two models have nearly the same headline recall, yet what reaches ASR differs
substantially. That difference comes from the default operating point, not from
the architecture.

Looking at the non-speech failures by type shows where the leakage concentrates.
Both models reliably reject synthetic noise. The difference shows up on real
recorded audio such as environmental sound and music: tuned Silero leaks very
little, while default FSMN-VAD accepts a large fraction of it.

### Speed and load

FSMN-VAD is faster on throughput once warm, but the picture flips on startup cost.
Silero's cached model loads almost instantly. FSMN-VAD takes noticeably longer to
load when warm and much longer on a cold first run that includes the download. A
long-lived service that loads once cares about steady-state speed; short-lived or
frequently restarted workers care about load time.

## Conclusion

Tuning, more than model choice, determines the operating point a VAD runs at.
Headline recall can look high while default post-processing passes non-speech at a
rate an ASR gate cannot accept. This is a property of the configuration, not the
architecture.

The same reasoning applies to any VAD. Decide which error is more expensive for
the path in question, then tune toward it:

- Strict gate (live or streaming input): a false positive becomes a hallucinated
  transcript in real time, so the operating point should favor rejecting
  non-speech, the direction tuning moved Silero.
- High-recall front end (uploaded files, offline batch): a user cannot re-record
  a file they already sent, so dropping real speech is the worst outcome, and the
  operating point should favor recall.

These two targets pull in opposite directions, so a single VAD at a single
operating point will be wrong for at least one path. A system that serves both
live streams and offline uploads is usually better off running a different VAD, or
the same VAD tuned differently, for each path rather than forcing one
configuration to cover both. VADs are cheap to load and run, so the cost of doing
this is low. In this study the split was tuned Silero for the strict live gate and
FSMN-VAD for the offline front end, though the routing decision matters more than
the specific pair.

Defaults are a reasonable starting point. Choosing a model for each path and
tuning it to that path's requirements is what produces a usable gate.

---

*Sources: [Silero VAD](https://github.com/snakers4/silero-vad) ·
[FunASR FSMN-VAD](https://huggingface.co/funasr/fsmn-vad)*
