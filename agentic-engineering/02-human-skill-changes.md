---
title: "Part 2 - Human Skill Changes"
header:
  overlay_image: /assets/images/hero-agentic-02.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-agentic-02.svg
sidebar:
  nav: "agentic"
---

*Part 2 of [The Future of Agentic Engineering](./agentic-engineering.md). If the
unit of execution becomes a verifiable loop, what happens to the human in the
loop.*

<figure class="align-center">
  <img src="/assets/images/paintings/part2-vitruvian-man.jpg" alt="Leonardo da Vinci, Vitruvian Man" title="Vitruvian Man — the comb-shaped profile: breadth across the lifecycle, depth where it counts">
  <figcaption>Leonardo da Vinci, <em>Vitruvian Man</em> (c. 1490). Breadth and proportion in one figure. Public domain, via Wikimedia Commons.</figcaption>
</figure>

Part 1 argued that agentic engineering changes the unit of execution from a
human task to a verifiable loop. This part asks what that does to the person
running it.

The answer is not that narrow specialists disappear. It is that the
highest-leverage human increasingly needs enough breadth to drive the whole
system: product intent, requirements, design, architecture, implementation,
quality, security, release, operations, and learning.

## The core shift

Before agentic systems, specialization was efficient because human throughput
was scarce and coordination was expensive. A product manager, requirements
analyst, designer, backend engineer, QA engineer, security reviewer, and release
engineer each held a defensible lane.

Agents make execution capacity elastic. One human can ask for requirements,
design alternatives, code changes, tests, release notes, and security review in
a single session. The limiting skill moves from "can I personally perform every
specialized task?" to "can I recognize what good looks like across the
lifecycle, steer agents toward it, and reject plausible but wrong work?"

That is a new profile: the accountable orchestrator-generalist. This person is
not the best coder, tester, designer, architect, reviewer, and release engineer.
They have enough fluency in each to set the goal, pick the right method, inspect
the evidence, and know when to pull in a deeper expert.

## Determinism, reframed

Strict determinism is the wrong expectation for LLM output. Even at low
temperature, context, tool state, model updates, and ambiguous instructions
shift behavior.

The workable goal is bounded repeatability:

- The problem is framed consistently.
- Inputs and context are explicit.
- Tools and permissions are scoped.
- Outputs are structured where possible.
- Tests and checks are reproducible.
- Decisions and assumptions are recorded.
- Human review gates are clear.
- Production rollback and monitoring exist.

The human's job is to make the outcome deterministic enough for the risk level.
A prototype tolerates more variance than a database migration, a payment flow,
an authentication change, or a production release.

## The skill shift

### From doing to framing

The old high-value skill was often execution: write the code, file the bug,
design the screen, draft the test plan. Those still matter, but the multiplier
now rewards framing.

Good framing:

- Defines the user or system actor.
- States the outcome.
- Names constraints.
- Separates requirements from guesses.
- Specifies acceptance evidence.
- Names non-goals.
- Gives the agent the right context, not all context.

A weak goal produces broad, confident work that is expensive to review. A strong
goal produces narrow, testable work.

### From prompting to context engineering

"Prompt engineering" is too small for durable agentic work. The real skill is
context engineering:

- Which files, docs, issues, tests, logs, and design records should the agent
  read?
- Which instructions belong in a global file, a role file, a skill, a one-time
  prompt, or a tool schema?
- What should carry across sessions?
- What should be dropped because it is stale or speculative?
- What evidence is required before the agent may continue?

Codex skills and MCP resources make this concrete. They let reusable
instructions, scripts, references, and external context become part of the
agent's working environment. The human designs that environment.

### From local expertise to lifecycle fluency

A twelve-role model is a useful map of the judgment required:

| Lens | What the human must be able to ask |
|---|---|
| Product | Does this matter to a user or business outcome? |
| Requirements | Can this be tested and scoped? |
| UX | Will the workflow make sense under real use? |
| Architecture | Does the design fit the system and future change? |
| Backend | Are data, APIs, validation, and failure modes correct? |
| Frontend | Are states, accessibility, and interaction behavior handled? |
| Integration | Do systems, environments, and third parties line up? |
| Code quality | Is the change simple, maintainable, and covered? |
| QA | What would prove this works and does not regress? |
| Security | What can be abused, leaked, bypassed, or misconfigured? |
| DevOps/SRE | Can this be deployed, observed, rolled back, and supported? |
| Documentation/feedback | Will users and support understand what changed? |

The human need not perform each role by hand every time. They need enough
vocabulary and judgment to invoke, compare, and verify those perspectives.

### From reviewing output to reviewing evidence

Human review used to center on artifacts: code, test plans, designs, tickets.
Agentic review centers on the evidence trail:

- What context did the agent inspect?
- What assumptions did it make?
- What files did it change?
- What tests did it run, and which did it skip?
- What failure did it observe?
- What tradeoff did it choose?
- What is still uncertain?

This is a different skill. A large polished answer can be less trustworthy than
a smaller one with clear evidence and stated limits.

### From coordination to orchestration

Coordination moves work among humans. Orchestration shapes a workflow among
humans, agents, tools, and gates. The orchestrator decides which tasks are safe
for autonomy, which need parallel agents, which need a specialist human, which
tools are allowed, which checks must pass, when to stop and ask, and when to
throw an agent's work away. That is closer to directing a small operating system
than working a ticket queue.

## Breadth is not shallow generalism

Two bad readings of the shift. The first: "everyone must become a full-stack
genius." Unrealistic and unnecessary. The second: "agents remove the need for
expertise." Dangerous.

The better model is a comb-shaped profile:

- One or two deep domains where the human can judge expert-level quality.
- Broad working literacy across the lifecycle.
- Strong systems thinking.
- Strong taste for evidence, simplicity, and user value.
- The habit of encoding lessons into instructions, tests, skills, templates, and
  tools.

Deep specialists get more valuable when they convert expertise into reusable
agentic assets. A strong QA engineer builds test-generation skills, defect
taxonomies, risk checklists, and release gates. A security reviewer builds
threat-model prompts, abuse-case templates, dependency scans, and
least-privilege tool policies. A designer builds design-review lenses and
accessibility checks. The specialists most at risk are those whose value is
local execution without explicit judgment, reusable standards, or
cross-functional communication.

## Skill stack for the human in the loop

### 1. Product and problem framing

Agents produce many solutions to the wrong problem. Product judgment gets more
valuable as the cost of plausible work falls.

- Write one-sentence problem statements.
- Separate user pain from proposed solution.
- Define a success metric before asking for implementation.
- Ask for alternatives before picking the first path.

### 2. Requirements and acceptance criteria

Agentic execution needs crisp stopping conditions. Requirements should become
executable checks where possible.

- Convert fuzzy goals into `Given / When / Then` criteria.
- Name edge cases and non-goals.
- Require tests or manual verification steps with each change.
- Keep traceability from goal to diff to test evidence.

### 3. Code reading and diff judgment

Even non-specialist orchestrators need code-reading fluency: inspect diffs, spot
accidental blast radius, read test failures, and ask useful review questions.

- Read diffs before summaries.
- Ask why each changed file needed to change.
- Check whether tests prove the stated behavior.
- Look for hidden coupling, migration risk, and error handling.

### 4. Testing and evaluation literacy

Testing is no longer a downstream phase. It is the control system.

- Know the difference between unit, integration, end-to-end, regression,
  security, and exploratory tests.
- Use evals for behavior that deterministic tests cannot capture.
- Treat flaky tests as workflow debt.
- Ask for a failing test before a fix when it fits.

### 5. Security and permission design

Agents with tools are operational actors. Think in least privilege, secrets,
sensitive data, dependency risk, and irreversible actions.

- Scope tool access to the task.
- Require confirmation for destructive or externally visible actions.
- Keep credentials out of prompts and logs.
- Ask for threat models on sensitive features.

### 6. Architecture and systems thinking

Agents are good at local edits and weak at preserving long-term architecture
unless it is explicit.

- Maintain architecture records and boundaries.
- Ask agents to explain how a change fits the system.
- Prefer small, reversible changes.
- Escalate when the agent proposes new infrastructure, data models, or major
  abstractions.

### 7. Economic judgment

Agentic work costs tokens, tool calls, cloud resources, review time,
opportunity cost, and risk. Cheap generation can become expensive integration.

- Decide when a task deserves a deep run, a quick run, or no run.
- Watch diff size, context size, and review time.
- Compare token cost against expected value and human time saved.
- Stop loops that are accumulating uncertainty.

### 8. Communication and decision logging

Agentic systems create many intermediate artifacts. The human turns them into
durable knowledge.

- Record decisions with options considered and rationale.
- Update instructions when a failure repeats.
- Promote stable workflows into skills.
- Keep summaries short enough for future agents to use.

## A maturity model

| Level | Human behavior | Risk |
|---|---|---|
| Operator | Asks for tasks and accepts summaries | High trust in plausible output |
| Reviewer | Reads diffs and asks for tests | Better quality, still reactive |
| Orchestrator | Designs loops, scopes tools, sequences agents, demands evidence | Strong leverage and control |
| System designer | Converts repeated lessons into skills, evals, templates, tools, and governance | Organization-level compounding |

The goal is not to make everyone a system designer overnight. It is to move
serious agentic work past operator mode.

## Where this points

The tooling around the orchestrator-generalist should train and support them:

- Keep role lenses, but express them as invocable skills and review gates.
- Add an orchestration guide for when to use single-agent, multi-agent, skill,
  MCP, or human escalation.
- Add acceptance-evidence templates for each workflow.
- Add a permission model for safe tool use.
- Add review-load and rework metrics so human bottlenecks are visible.
- Add promotion paths from ad hoc prompts to reusable skills.

## Sources

- [Principles behind the Agile Manifesto](https://agilemanifesto.org/principles.html)
- [DORA Research: 2025 State of AI-assisted Software Development](https://dora.dev/research/2025/dora-report/)
- [DORA: Choosing measurement frameworks to fit your organizational goals](https://dora.dev/research/2025/measurement-frameworks/)
- [OpenAI Codex: Prompting](https://developers.openai.com/codex/prompting)
- [OpenAI Codex: Agent Skills](https://developers.openai.com/codex/skills)
- [Model Context Protocol: Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)
- [World Economic Forum: Future of Jobs Report 2025](https://www.weforum.org/publications/the-future-of-jobs-report-2025/)
- [UNESCO AI competency frameworks for teachers and students](https://www.unesco.org/en/digital-education/ai-future-learning/competency-frameworks)
- [Human-In-The-Loop Software Development Agents: Challenges and Future Directions](https://arxiv.org/abs/2506.11009)

---

*Previous: [Part 1 - Principles and Methodologies](./01-principles-and-methodologies.md). Next: [Part 3 - Cadence and Mental Discipline](./03-cadence-and-mental-discipline.md). [Series index](./agentic-engineering.md).*
