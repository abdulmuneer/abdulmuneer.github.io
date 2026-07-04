---
title: "The Future of Agentic Engineering"
permalink: /agentic-engineering/
header:
  overlay_image: /assets/images/hero-agentic.svg
  overlay_filter: 0.5
sidebar:
  nav: "agentic"
toc: false
author_profile: false
---

A five-part series on where software work is heading as coding agents move from
novelty to daily tool.

The question that started it: **in an agentic world, how would you set up and run
an engineering organization?** Not "can an agent write this function," but how the
organization itself changes - the roles, the gates, the cadence, and the way work
gets delegated and verified once agents are part of the team.

I wrote this guide to answer that for myself. Across eighteen years building
software, and the last nine spent across the AI stack - hardware, frameworks,
models, and the applications on top - I keep landing on the same conclusion: the
hard part is rarely the code an agent produces. It is the system around it - who
steers, who verifies, and what has to be true before the result ships.

It grew out of a companion repository,
[`agentic_engineering`](https://github.com/abdulmuneer/agentic_engineering/), a
working operating model of roles, trackers, gates, and learning artifacts. I
treat it as a seed to build on, not a finished answer. The recommendations here
hold whether or not you use anything like it.

<figure class="align-center">
  <img src="/assets/images/paintings/landing-school-of-athens.jpg" alt="Raphael, The School of Athens" title="The School of Athens — accountable orchestration: many minds coordinated into one composed system">
  <figcaption>Raphael, <em>The School of Athens</em> (1509–1511). Many minds, one composed system. Public domain, via Wikimedia Commons.</figcaption>
</figure>

## The thesis

Agentic engineering is easy to caricature as "AI writes code." The real shape is
organizational. Humans design, steer, verify, and improve systems of
goal-directed agents that gather context, use tools, change artifacts, run
checks, and produce evidence inside bounded workflows. The job moves from writing
every line to running that system well.

The durable principles of software and product work still hold: customer value,
small batches, technical excellence, working software, independent verification,
risk management, observability, sustainable pace, and learning. What changes is
the methods. Agents, skills, MCP tools, subagents, worktrees, memory,
compaction, evals, and repeatable loops turn parts of the lifecycle into
something you can execute.

The human shift is from narrow task execution toward accountable orchestration.
The people who gain the most can move across product, requirements, design,
architecture, engineering, quality, security, release, operations, and learning
well enough to frame goals, set boundaries, review evidence, and integrate what
comes back.

## The series

- [Part 1 - Principles and Methodologies](./01-principles-and-methodologies.md) - what stays fixed, what becomes executable, and why a writing loop only counts as a slice of the SDLC once it verifies.
- [Part 2 - Human Skill Changes](./02-human-skill-changes.md) - the shift from doing to framing, the comb-shaped skill profile, and determinism reframed as bounded repeatability.
- [Part 3 - Cadence and Mental Discipline](./03-cadence-and-mental-discipline.md) - agents run around the clock; humans should not. Tempo control instead of longer hours, with lessons from automation, aviation, lean, and SRE.
- [Part 4 - Compounding and Equilibrium](./04-compounding-and-equilibrium.md) - how good work compounds into reusable assets, the limits that stop it running away, and who gains.
- [Part 5 - Wellbeing, Sustainability, and Education](./05-wellbeing-and-education.md) - wellbeing as part of the control system, and what children actually need when the tools keep changing.

## The argument in sequence

**1. Principles stay, methods change.** The principles that drove good software
for decades still matter. Agentic systems do not remove requirements, tests,
review, release discipline, or learning; they compress parts of the lifecycle
into executable loops. A loop without verification is only automation. A loop
with evidence becomes an executable slice of software delivery.

**2. The human skill profile broadens.** Agentic leverage rewards
orchestrator-generalists. This does not make everyone a shallow generalist. It
means the human in the loop needs enough breadth to recognize good and bad work
across the lifecycle. The strongest profile is comb-shaped: deep in one or two
domains, fluent across the rest, with strong judgment about evidence, risk, and
user value, and the habit of encoding lessons into tests, tools, skills, and
templates. Determinism becomes bounded repeatability - not perfect determinism,
but reliable-enough workflows built from explicit context, scoped tools,
structured outputs, reproducible checks, decision logs, and review gates.

**3. Control tempo, do not match agent speed.** Agents run longer, faster, and
in parallel. Humans cannot and should not try to keep up through longer hours.
The adaptation is tempo control: review windows instead of constant
interruption, work packets instead of endless threads, WIP limits set by human
review capacity, checkpoints before risky changes, stop rules for drifting
agents, and recovery treated as part of the system. Automation, aviation, lean
production, SRE, and automated trading all point the same way - speed needs
observability, mode awareness, stop rules, and governors.

**4. Compounding is real but bounded.** Agentic work compounds when success
improves future work: code becomes tests, tests become confidence, repeated
prompts become skills, decisions become architecture records, incidents become
runbooks. It stabilizes against real limits - attention, verification cost,
maintenance burden, context complexity, token and compute cost, risk and
governance, the supply of valuable problems, and how fast an organization can
absorb change. The equilibrium is not infinite acceleration. Prototypes get
cheaper, production stays hard, expert review gets scarcer, small accountable
teams gain leverage, and governance becomes productive once it is built into the
tools.

**5. Wellbeing and education become strategic.** If humans stay responsible for
judgment, their clarity, sleep, attention, ethics, learning, and social
grounding are operational, not incidental. The future is best met with
disciplined agency: skip the panic, skip the complacency, learn the tools,
preserve the human fundamentals, convert lessons into durable systems, and keep
responsibility close to the people affected. Education should not collapse into
"teach children to prompt." Prompting will change; the durable skill is the
ability to think, build, verify, care, and adapt.

## System model

<figure class="align-center">
  <img src="/assets/images/diagram-system-model.svg" alt="System model: durable principles feed agentic methodologies, which the human orchestrates into bounded agent loops that produce evidence and learning assets; a second loop runs orchestration through cadence control and sustained capacity.">
</figure>

## Where this points

A role-and-document scaffold is a useful classical operating model: it names
roles, trackers, gates, and learning artifacts. The companion repo,
[`agentic_engineering`](https://github.com/abdulmuneer/agentic_engineering/),
is one such scaffold. The more useful future version evolves from a static
scaffold into an agentic operating system:

- Turn role files into role lenses, review gates, and reusable skills.
- Build a loop library for common workflows: discovery, requirements, design
  review, implementation, test hardening, security review, release readiness,
  incident learning.
- Standardize work-packet templates for agent output: goal, context, files
  changed, tests run, evidence, risks, open questions, next action.
- Write down safe tool-use rules: permissions, confirmation gates, sandbox
  rules, external-action rules, audit logging.
- Set WIP and cadence controls: active-run limits, review windows, checkpoint
  rules, safe-overnight classifications.
- Add compounding mechanisms: a skill registry, an eval registry, a
  decision-to-instruction path, test promotion, runbook promotion.
- Track the right metrics: accepted output, rework, review burden, defect
  escape, cost, human interruption, recovery risk.
- Build training paths for orchestrator-generalists.

## Practical north star

The best version of this operating model should help a human do four things:

1. Choose the right work.
2. Delegate bounded loops safely.
3. Verify outcomes with evidence.
4. Convert learning into a stronger system.

If it only helps agents produce more artifacts, it misses the point. If it helps
humans preserve principles while upgrading methods, it becomes a real operating
system for responsible agentic software development.

## Research notes

This is grounded in current public sources on AI agents, Codex skills, MCP,
DORA, Agile, SRE, the NIST AI risk framework, AI labor and productivity
research, automation human factors, WEF skills research, and UNESCO/OECD
education guidance, alongside my own build experience.

## Sources

- [Principles behind the Agile Manifesto](https://agilemanifesto.org/principles.html)
- [DORA Research: 2024 Accelerate State of DevOps Report](https://dora.dev/research/2024/dora-report/)
- [DORA Research: 2025 State of AI-assisted Software Development](https://dora.dev/research/2025/dora-report/)
- [OpenAI Agents SDK: Agents](https://openai.github.io/openai-agents-python/agents/)
- [OpenAI Codex: Prompting](https://developers.openai.com/codex/prompting)
- [OpenAI Codex: Agent Skills](https://developers.openai.com/codex/skills)
- [OpenAI Codex: Subagents](https://developers.openai.com/codex/subagents)
- [Model Context Protocol: Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [Model Context Protocol: Resources](https://modelcontextprotocol.io/specification/2025-06-18/server/resources)
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)
- [Google SRE Book: Eliminating Toil](https://sre.google/sre-book/eliminating-toil/)
- [Lisanne Bainbridge, Ironies of Automation](https://web.archive.org/web/20200717054958if_/https://www.ise.ncsu.edu/wp-content/uploads/2017/02/Bainbridge_1983_Automatica.pdf)
- [Human-In-The-Loop Software Development Agents: Challenges and Future Directions](https://arxiv.org/abs/2506.11009)
- [Measuring AI Ability to Complete Long Tasks](https://arxiv.org/abs/2503.14499)
- [Measuring the Impact of Early-2025 AI on Experienced Open-Source Developer Productivity](https://arxiv.org/abs/2507.09089)
- [World Economic Forum: Future of Jobs Report 2025](https://www.weforum.org/publications/the-future-of-jobs-report-2025/)
- [UNESCO AI competency frameworks for teachers and students](https://www.unesco.org/en/digital-education/ai-future-learning/competency-frameworks)
- [OECD Future of Education and Skills 2030](https://www.oecd.org/en/about/projects/future-of-education-and-skills-2030.html)

---

*Back to [the blog home](../index.md).*
