---
title: "ASR - Notes from Building Speech-to-Text"
permalink: /asr/
header:
  overlay_image: /assets/images/hero-asr.svg
  overlay_filter: 0.5
sidebar:
  nav: "asr"
toc: false
author_profile: false
---

Field notes from building and tuning automatic speech recognition (ASR)
pipelines - the components that sit around the model, the trade-offs that decide
quality in practice, and what the experiments actually showed.

## The series

- [Tuning Voice Activity Detection for ASR Gating](./tuning-vad-for-asr.md) - why a VAD's defaults aren't enough for ASR, how tuning changes the gate, and why the right answer is often a different VAD per use case. Silero VAD and FunASR's FSMN-VAD as worked examples.

*More to come.*

---

*Back to [the blog home](../index.md).*
