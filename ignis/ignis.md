---
title: "Ignis - Finding Your Mojo from DwarfStar"
permalink: /ignis/
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
sidebar:
  nav: "ignis"
toc: false
author_profile: false
---

A six-part blog series: field notes from building **Ignis**, a Mojo-native agent
harness that runs a MAX-served LLM in the same OS process as the control plane.
Less "release notes," more "what I found going into the innards of Mojo and MAX."

{: .notice--info}
**New to Mojo or MAX?** Parts 3 and 4 each open with a from-scratch, five-minute primer - enough to onboard someone who has never touched either before diving into the assessment. If you already know the tools, skip those intros and go straight to the details; the rest of the series doesn't repeat them.

## The series

- [Part 0 - The Curiosity and the Plan](./00-curiosity-and-the-plan.md) - the trailhead: what made me curious about Mojo and MAX, the `ds4` spark, the in-process bet, and the M0→M5 plan I set out with.
- [Part 1 - What It Is, and How to Run It](./01-what-ignis-is.md) - the artifact and a functional user guide: the in-process design, the `Engine` trait everything hangs off, the architecture and control flow, extensibility, the examples, and how to build and run it.
- [Part 2 - What Was Achieved](./02-what-was-achieved.md) - a scorecard against the plan, headlined by durable cross-process session resume, with the numbers I measured and the ones I deliberately didn't.
- [Part 3 - Mojo, the Language](./03-mojo-the-language.md) - a from-scratch primer, then an assessment of Mojo at 1.0 beta from building in it: where it matured, where it bites, and why batteries-not-included decides fit.
- [Part 4 - MAX, the Platform](./04-max-the-platform.md) - a from-scratch primer, what MAX is and its place among NVIDIA's stack, vLLM/SGLang, and the MLIR compilers; then the deep climax - compiling Ignis's refund policy into the decoder two ways.
- [Part 5 - My Journey, and a Thank-You](./05-the-journey.md) - the trail told as a trail, the verdict, and a genuine appreciation for what Modular built.

---

*Back to [the blog home](../index.md).*
