---
title: "Part 1 - Principles and Methodologies"
header:
  overlay_image: /assets/images/hero-agentic-01.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-agentic-01.svg
sidebar:
  nav: "agentic"
---

*Part 1 of [The Future of Agentic Engineering](./agentic-engineering.md). What
separates the durable principles of software work from the newer methods agents
bring.*

<figure class="align-center">
  <img src="/assets/images/paintings/part1-vermeer-geographer.jpg" alt="Johannes Vermeer, The Geographer" title="The Geographer — a loop only counts once it verifies: disciplined craft, instruments, evidence">
  <figcaption>Johannes Vermeer, <em>The Geographer</em> (c. 1668–69). Disciplined craft, instruments, verification. Public domain, via Wikimedia Commons.</figcaption>
</figure>

## The split

Agentic software development does not repeal the old principles of good software
work. It changes the unit of execution.

The old unit was usually a person, team, sprint, ticket, or pull request. The
emerging unit is a loop: an agent or agent group receives a goal, gathers
context, plans, edits, tests, explains, and either asks for approval or
continues. This loop can compress pieces of the classical SDLC into minutes, but
it still needs the controls that made software delivery work before - customer
value, small batches, explicit requirements, technical excellence, independent
verification, risk management, observability, and sustainable pace.

The practical difference is that methodology becomes executable. Instructions,
skills, MCP servers, tool permissions, worktrees, subagents, tests, evals, and
review prompts are not documentation about what the system should do. They shape
what it can do.

## What a classical operating model already encodes

A responsible-minimum software organization already expresses most of the
required judgment:

- Intake and product direction.
- External knowledge review.
- Requirements and acceptance criteria.
- UX and architecture.
- Sprint planning.
- Backend, frontend, and integration implementation.
- Code quality, QA, and security review.
- Release, deployment, monitoring, support, and retrospectives.

The companion repo,
[`agentic_engineering`](https://github.com/abdulmuneer/agentic_engineering/),
encodes exactly this as role files, trackers, and gates. That structure captures
the breadth of thinking it takes to ship real software. Its risk is that it looks
like a fixed twelve-role human org chart. In an
agentic system these roles should become lenses and gates, not necessarily
people. The perspectives are worth keeping; one human can instantiate many of
them through agents, skills, checklists, and validation loops.

## Principles that stay stable

### 1. Customer value beats activity

The Agile Manifesto puts customer satisfaction through early and continuous
delivery of valuable software first, and makes working software the primary
measure of progress. Agents make activity cheap - branches, diffs, documents,
tests, tickets, and dashboards multiply fast. That makes the principle more
important, not less. The question is not "how many agents ran?" but "what user,
operational, or learning value changed?"

Implication: every loop needs an outcome statement and acceptance evidence. An
agent that cannot verify the value has only produced motion.

### 2. Small batches still win

Agile favors frequent working software on short timescales, and DORA keeps
returning to fundamentals like small batches, testing, and stable priorities.
Agents tempt you to delegate huge, vague goals, because they keep working while
you sleep. That raises context drift, review burden, and hidden rework.

Implication: slice agentic tasks by verifiability, not by how much an agent can
attempt. The right task is large enough to produce value and small enough that
its diff, tests, and rationale can be reviewed by a tired human.

### 3. Technical excellence is a speed strategy

Agile links technical excellence and good design to agility. Agents sharpen the
point. A repo with clear architecture, tests, scripts, conventions, and
documented setup lets agents work with confidence. An ambiguous repo makes them
burn tokens rediscovering intent, or generate plausible but wrong code.

Implication: internal platforms, good test harnesses, stable local setup, typed
interfaces, code owners, and architecture records are not overhead. They are
agent affordances.

### 4. Human judgment moves upstream and downstream

Humans do less literal typing and more task framing, boundary setting, evidence
evaluation, and final accountability. The Model Context Protocol frames tools as
model-controlled while recommending user visibility and human confirmation for
operations. The same rule should govern coding agents: autonomy is useful only
inside a clear boundary of what the agent may do and what needs a human.

Implication: humans should approve goals, permissions, sensitive operations,
irreversible changes, and releases. Agents can do the search, edit, test, and
explanation work inside those boundaries.

### 5. Risk management must be layered

NIST's AI Risk Management Framework builds trustworthiness into design,
development, use, and evaluation. Software teams already know defense in depth
from security, QA, release management, and SRE. Agentic systems need the same
layered model, because any single defense fails: instructions get ignored, tests
stay incomplete, review gets tired, and tool permissions run too broad.

Implication: a safe workflow combines sandboxing, least-privilege tools, scoped
tasks, tests, static analysis, human review, audit logs, rollback plans, and
production monitoring.

### 6. Sustainability is a delivery constraint

Agile names a pace that can be maintained indefinitely. Google SRE's work on
toil draws the boundary: repetitive, manual, automatable, interrupt-driven work
that scales linearly is toxic when it dominates. Agents can remove toil, but
they can also create new toil - supervising too many runs, reviewing large
diffs, managing failed branches, debugging hallucinated assumptions, and
absorbing constant notifications.

Implication: measure human review load, interruption rate, rework, and fatigue,
not just agent throughput.

## New methodologies

<figure class="align-center">
  <img src="/assets/images/principles.png" alt="Fortress and tumor scenarios illustrating one convergence principle across two different contexts" title="One principle, many contexts: when the direct path is too costly, split into many safe paths that converge on the target">
  <figcaption>The same principle in two contexts: when a direct path is too risky or too damaging, split into many safe paths that converge on the target. The principle holds while the context changes — the through-line of everything below.</figcaption>
</figure>

### Agents

An agent is not just a chat model. In the OpenAI Agents SDK it is an LLM
configured with instructions, tools, optional handoffs, guardrails, structured
outputs, lifecycle hooks, and sessions. The engineering object is the whole
runtime: model, prompt, context, tools, policy, memory, and observability.

- Use single agents for focused tasks with clear verification.
- Use manager-style orchestration when one controller should hold context and
  call specialists as tools.
- Use handoffs when a specialist should take over the task state.
- Use lifecycle hooks, traces, and structured outputs when the workflow must be
  inspected or evaluated.

### Skills

Skills package reusable workflow knowledge. Codex skills are directories with a
`SKILL.md` file plus optional scripts, references, assets, and configuration.
They load progressively: only the name, description, and path load first; the
full instructions load when the skill is selected.

- Turn repeated human craft into explicit reusable instructions.
- Put narrow, high-signal workflows into skills instead of long global prompts.
- Store scripts and templates with the skill when prose is not enough for
  reliable execution.
- Treat third-party skills as supply-chain inputs; a skill carries procedural
  authority.

### MCP and connectors

MCP standardizes how models discover and invoke tools or read resources. Tools
expose callable actions with schemas; resources expose context such as files,
schemas, or application state. The security guidance matters: tools should be
visible, sensitive operations confirmable, inputs and outputs validated, and
tool use logged.

- Convert organizational systems into bounded tool surfaces.
- Prefer typed, narrow tools over broad shell access where you can.
- Separate resources from actions - reading context is not mutating state.
- Treat tool descriptions and annotations as untrusted unless the server is.

### Loops

The loop is the biggest shift. Codex calls the model, performs actions like file
reads, edits, and tool calls, and repeats until the task completes or is
cancelled. That is a miniature SDLC:

<figure class="align-center">
  <img src="/assets/images/diagram-agent-loop.svg" alt="The agent loop: goal, context gathering, plan, change, verify, then a decision gate. If the evidence is not good enough it loops back to context gathering; if it is, it goes to human review or merge.">
</figure>

One correction to the tempting version of this idea: a writing loop is a subset
of the SDLC only when it includes verification and decision gates. "Keep working
until done" is not SDLC. A loop that gathers context, plans, implements, tests,
records assumptions, and stops at a review gate is an executable slice of it.

### Subagents and parallelism

Subagents split work into parallel perspectives: explorer, worker, security
reviewer, test reviewer, documentation reviewer, performance reviewer. Codex
notes that subagent workflows suit highly parallel complex tasks and cost more
tokens than a comparable single-agent run.

- Use subagents for independent perspectives, not merely more output.
- Prefer parallel exploration, review, and test generation over parallel edits
  to the same files.
- Use worktrees or branch isolation when multiple agents may edit code.
- Consolidate results through one accountable human or manager agent.

### Verification and evals

The methodology is not "prompt better." It is "make the work verifiable." Good
prompts carry reproduction steps, validation commands, linting, and pre-commit
checks. Research on human-in-the-loop software agents flags unit-testing cost
and variability in LLM-based evaluation as major challenges, which pushes teams
toward layered evidence:

- Automated tests for behavior.
- Static analysis and type checks for structure.
- Lint and formatting for consistency.
- Security scanning for known risk classes.
- Human review for intent, tradeoffs, and unstated constraints.
- Production telemetry for real-world feedback.

### Memory and compaction

Agentic work spans long threads, many files, and repeated sessions. Memory and
compaction are methodology, not convenience: they decide what the agent
remembers, forgets, compresses, or overweights.

- Keep durable project knowledge in versioned files, not just chat history.
- Compact around decisions, assumptions, tests run, open risks, and next
  actions.
- Do not let stale memory override current source, current docs, or current
  product intent.

## Classical SDLC, reinterpreted

| Classical concern | Agentic method | Human responsibility |
|---|---|---|
| Idea intake | Goal prompt, issue, product brief | Decide whether the goal matters |
| Requirements | Agent-assisted story and acceptance-criteria drafting | Ensure testability and business meaning |
| Design | UX, architecture, threat-model agents | Choose tradeoffs and reject incoherent designs |
| Implementation | Worker agents, tools, codebase context | Scope, permissions, and review |
| Testing | Agent-generated tests, CI, evals | Judge coverage and risk |
| Review | Subagent review, code review, security review | Resolve conflicts and own approval |
| Release | Deployment scripts, checklists, runbooks | Decide go/no-go and rollback readiness |
| Operations | Monitoring, incident agents, support summarization | Maintain situational awareness |
| Learning | Retrospective summaries, skills, updated rules | Convert lessons into system changes |

## Where this points

A static role-based folder system should evolve into an agentic operating
system with:

- Role lenses expressed as reusable skills and review prompts.
- Trackers that agents can read and update through safe tools.
- A loop library for common workflows: discovery, requirements, design review,
  implementation, test hardening, release readiness, incident learning.
- Explicit gates for permissions, irreversible actions, security-sensitive
  changes, and release.
- Metrics for value, stability, review burden, rework, cost, and sustained human
  capacity.
- A learning mechanism that promotes repeated successful workflows into skills.

## Working definition

Agentic engineering is software development in which humans design, steer,
verify, and improve systems of goal-directed AI agents that gather context, use
tools, modify artifacts, run checks, and produce evidence inside bounded
workflows.

That is the executable management of the whole product-development loop, not just
code generation.

## Sources

- [Principles behind the Agile Manifesto](https://agilemanifesto.org/principles.html)
- [DORA Research: 2024 Accelerate State of DevOps Report](https://dora.dev/research/2024/dora-report/)
- [DORA Research: 2025 State of AI-assisted Software Development](https://dora.dev/research/2025/dora-report/)
- [DORA: Choosing measurement frameworks to fit your organizational goals](https://dora.dev/research/2025/measurement-frameworks/)
- [OpenAI Agents SDK: Agents](https://openai.github.io/openai-agents-python/agents/)
- [OpenAI Codex: Prompting](https://developers.openai.com/codex/prompting)
- [OpenAI Codex: Agent Skills](https://developers.openai.com/codex/skills)
- [OpenAI Codex: Subagents](https://developers.openai.com/codex/subagents)
- [Model Context Protocol: Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [Model Context Protocol: Resources](https://modelcontextprotocol.io/specification/2025-06-18/server/resources)
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)
- [Google SRE Book: Eliminating Toil](https://sre.google/sre-book/eliminating-toil/)
- [Human-In-The-Loop Software Development Agents: Challenges and Future Directions](https://arxiv.org/abs/2506.11009)

---

*Next: [Part 2 - Human Skill Changes](./02-human-skill-changes.md). [Series index](./agentic-engineering.md).*
