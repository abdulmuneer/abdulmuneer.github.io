---
title: "ASR Systems"
permalink: /asr/
header:
  overlay_image: /assets/images/hero-asr.svg
  overlay_filter: 0.55
sidebar:
  nav: "asr"
toc: false
author_profile: false
---

A technical series on ASR systems: the parts around the recognizer that decide whether speech is useful, attributable, observable, and safe to send downstream.

The focus is practical architecture rather than leaderboard modeling: session state, streaming control flow, speaker following, evaluation, rollout, privacy boundaries, and the decisions that determine whether a recognizer behaves well in real audio.

## The series

- [Part 0 - Target Speaker Following for ASR](./tse_guide.md) - how to add target speaker following in front of ASR using a three-route contract: pass clean target speech, extract recoverable overlap, and cut off unusable or non-target audio.

More parts will fill in the rest of the ASR stack as they land.

---

*Back to [the blog home](../index.md).*
