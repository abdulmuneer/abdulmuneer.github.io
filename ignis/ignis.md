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

A six-part account of building **Ignis**, a Mojo agent harness that runs a MAX
model in the same OS process as its control plane. It records the implemented
interfaces, failed approaches, measurements, and remaining Python boundaries.

{: .notice--info}
**New to Mojo or MAX?** Parts 3 and 4 define the language and platform concepts
used by the rest of the series. Readers familiar with them can skip those
introductions.

The repository now also includes a model-free local knowledge-search program,
not only a fixed retrieval demonstration. It indexes Markdown and text trees in
SQLite, returns line citations tied to an atomic snapshot, and exposes the same
read-only contract through Python, a Mojo bridge, a CLI, and an authenticated
loopback HTTP service. Part 1 covers how to run it; Parts 2–5 explain what it
changed about my view of the Python–Mojo boundary.

## The series

- [Part 0 - The Curiosity and the Plan](./00-curiosity-and-the-plan.md) - the trailhead: what made me curious about Mojo and MAX, the `ds4` spark, the in-process bet, and the M0→M5 plan I set out with.
- [Part 1 - What It Is, and How to Run It](./01-what-ignis-is.md) - architecture, control flow, extension interfaces, commands, and the durable local knowledge-search program.
- [Part 2 - What Was Achieved](./02-what-was-achieved.md) - results against the original plan, including session resume, semantic RAG, persistent cited search, and the measurements not performed.
- [Part 3 - Mojo, the Language](./03-mojo-the-language.md) - Mojo 1.0 beta in practice, including ownership, missing batteries, and the explicit Mojo-to-Python service boundary.
- [Part 4 - MAX, the Platform](./04-max-the-platform.md) - MAX's place in the inference stack, two decoder policy implementations, and the division between MAX, Mojo compute, and Python persistence.
- [Part 5 - My Journey](./05-the-journey.md) - the implementation sequence and the resulting language and runtime boundary.

---

*Back to [the blog home](../index.md).*
