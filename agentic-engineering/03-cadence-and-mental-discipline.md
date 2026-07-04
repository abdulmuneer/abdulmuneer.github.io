---
title: "Part 3 - Cadence and Mental Discipline"
header:
  overlay_image: /assets/images/hero-agentic-03.svg
  overlay_filter: 0.5
  teaser: /assets/images/hero-agentic-03.svg
sidebar:
  nav: "agentic"
---

*Part 3 of [The Future of Agentic Engineering](./agentic-engineering.md). Agents
run around the clock. Humans should not try to keep up.*

<figure class="align-center">
  <img src="/assets/images/paintings/part3-great-wave.jpg" alt="Katsushika Hokusai, The Great Wave off Kanagawa" title="The Great Wave off Kanagawa — control tempo, don't match it: immense force held in a composed frame">
  <figcaption>Katsushika Hokusai, <em>The Great Wave off Kanagawa</em> (c. 1831). Immense force held in a composed frame. Public domain, via Wikimedia Commons.</figcaption>
</figure>

Part 2 described the shift from narrow execution toward orchestration. This part
asks how humans adjust to a new cadence: agents work, retry, fork, summarize, and
generate while humans still need sleep, attention, social context, judgment, and
recovery.

## The real problem is asymmetry

The cadence problem is not that agents are fast. It is that the workers no longer
share the same constraints.

When every worker is human, everyone needs breaks, sleep, conversation, and time
to form judgment. When agents enter the loop, execution continues across nights,
weekends, and parallel branches. That creates an illusion: that the human should
keep up by extending the workday.

Wrong adaptation. The human should redesign the system so agent work arrives in
reviewable batches, with evidence, limits, and stopping points. The discipline is
not hustle. It is control of tempo.

## Historical parallels

### Automation and the irony of supervision

Lisanne Bainbridge's "Ironies of Automation" still holds: automation removes
routine manual work while leaving humans responsible for rare, difficult,
high-stakes intervention. The operator gets less practiced at the manual task,
yet is expected to take over when automation fails.

Agentic engineering repeats the pattern. Agents handle routine edits, summaries,
tests, and docs, and the human gets pulled in exactly when the problem is
ambiguous, cross-cutting, or risky. That calls for active situational awareness,
not passive trust.

Lesson: do not let agents run so far ahead that the human loses the thread.

### Aviation autopilot

Cockpit automation reduces workload in normal flight but creates mode-awareness
problems. Pilots must know what the automation is doing, what mode it is in, and
when to intervene. The agentic version:

- What task is the agent actually pursuing?
- Which files did it touch?
- Which assumptions did it make?
- Which tools did it use?
- Which checks passed, and which was skipped?
- Is it exploring, implementing, repairing, or reviewing?

Lesson: every long-running workflow needs visible mode state.

### Factory automation and stop-the-line

Lean production did not just make machines faster. It added standard work,
visible queues, WIP limits, and stop-the-line authority. Speed was made safe
through observability and the right to interrupt. The agentic version:

- Limit concurrent runs.
- Make queues visible.
- Require checkpoint summaries.
- Let humans and agents stop work when the evidence is poor.
- Promote repeated defects into process changes.

Lesson: throughput without stop rules becomes quality debt.

### DevOps, on-call, and SRE

DevOps and SRE already faced asymmetric cadence. Services run continuously,
incidents happen at night, alerts interrupt recovery. SRE answered with error
budgets, toil reduction, alert quality, runbooks, incident roles, and blameless
postmortems. Agents are not production services, but they create operational
load: notifications, diffs, branches, tool approvals, failed tests, review
queues.

Lesson: agentic work needs an operational model, not just a chat window.

### Financial markets and high-frequency trading

Automated trading made speed a weapon, and then required circuit breakers, risk
limits, kill switches, and compliance controls. The fastest actor is not the best
actor; uncontrolled speed amplifies mistakes. The agentic version:

- Set budget limits.
- Use sandboxed environments.
- Require approval for external actions.
- Stop runaway loops.
- Apply stronger controls to production-affecting tasks.

Lesson: speed needs governors.

## The new working cadence

### From continuous attention to scheduled review

Do not live inside the agent stream. Define review windows. An example:

- Morning: inspect overnight outputs; accept, reject, prioritize.
- Midday: run focused interactive sessions for ambiguous tasks.
- Afternoon: review diffs, tests, and decisions.
- End of day: queue bounded overnight tasks with explicit stop conditions.

Agent work should wait for human review rather than interrupt it.

### From chat threads to work packets

Long conversations are hard to review. Package work as:

- Goal.
- Context used.
- Files changed.
- Tests run.
- Evidence.
- Risks.
- Open questions.
- Recommended next action.

This mirrors a normal tracker, with agent-specific evidence added.

### From parallelism to WIP limits

It is easy to run many branches at once, and dangerous when review capacity is
fixed. A simple rule: do not start more agent work than you can review in the
next window. Useful limits:

- Maximum active branches.
- Maximum unreviewed diff size.
- Maximum autonomous runtime.
- Maximum token or tool budget.
- Maximum open decisions.
- Maximum unresolved test failures.

Set the limit by human review bandwidth, not agent availability.

### From real-time supervision to checkpointing

You should not watch every tool call. Set checkpoints at natural boundaries:

- After context gathering.
- Before large edits.
- After the first failing test is reproduced.
- Before database or infrastructure changes.
- After verification.
- Before merge, release, or any external side effect.

Checkpointing keeps the human in control without turning them into a babysitter.

## Mental disciplines to build

### 1. Tempo discipline

Deciding whether work should be synchronous, asynchronous, parallel, paused, or
stopped.

- Does this need my live judgment?
- Can this run safely while I sleep?
- What is the maximum acceptable drift before review?
- What evidence must exist before I look again?

### 2. Attention budgeting

Attention is the scarce resource. Spend tokens to save it, not to produce more
than a human can absorb.

- What is the one decision I need to make next?
- What can be summarized?
- What must be inspected directly?
- Which alerts should be silenced because they need no action?

### 3. Trust calibration

Neither distrust everything nor accept everything. Trust should track task risk,
evidence quality, the agent's track record, and verification strength.

- What did the agent actually verify?
- Is the output grounded in current files and tests?
- Familiar low-risk pattern, or novel high-risk change?
- Would I approve this from a junior engineer?

### 4. Situational awareness

Knowing the current goal, system state, risk state, and next decision. It decays
when too many agents run without summaries.

- Keep a visible active-work list.
- Use short end-of-session handoffs.
- Record assumptions and decisions.
- Re-read the diff and tests before trusting the summary.

### 5. Stop discipline

Stopping is an active skill. Stop agents that loop, widen scope, accumulate
uncertainty, or produce work that cannot be reviewed. Signals:

- The agent changes unrelated files.
- It cannot reproduce the failure.
- Tests are skipped without explanation.
- The diff grows faster than understanding.
- The same error repeats.
- The task needs a product or security decision that was not delegated.

### 6. Recovery discipline

Agentic work creates ambient urgency - there is always another run you could
start.

- Define an end-of-day queue, not an endless session.
- Do not review high-risk changes when tired.
- Treat sleep as a design constraint.
- Separate exploratory runs from approval decisions.
- Protect weekends and breaks unless production risk demands otherwise.

## Thought experiment: the overnight agent

Say a human starts five overnight agents:

1. One refactors authentication.
2. One updates dependencies.
3. One writes tests.
4. One drafts release notes.
5. One investigates support tickets.

By morning all five report success. The naive human now has more work, not less:
large diffs, possible conflicts, uncertain assumptions, and review pressure. A
better setup:

- Auth agent may only inspect, propose, and write a risk plan.
- Dependency agent may update one package group and run the dependency suite.
- Test agent may add tests but not touch production code.
- Release-notes agent may draft from merged commits only.
- Support agent may cluster issues and propose backlog items, not edit code.

The second setup respects cadence. Agents work; reviewability survives.

## Practical operating rules

**Before starting agents:** define the outcome, allowed files or systems, stop
conditions, evidence required, review time, and budget.

**During work:** prefer checkpoints over live monitoring, keep parallel agents
independent, prevent two agents from editing the same area unless isolated, stop
when the agent changes task class, and capture useful discoveries immediately.

**After work:** review diffs before summaries, read failed-test logs, record
decisions, promote repeated fixes into skills or tests, and delete abandoned
branches and stale artifacts.

## Cadence metrics

Track human cadence explicitly, beside delivery and quality metrics:

| Metric | Why it matters |
|---|---|
| Unreviewed agent outputs | Shows whether agents outrun humans |
| Average diff size per review | Predicts review fatigue and defect risk |
| Agent rework rate | Shows poor framing or weak verification |
| Human interruption count | Measures attention damage |
| Time from agent completion to human decision | Reveals bottlenecks |
| Autonomous runtime before checkpoint | Captures drift risk |
| Night/weekend approval count | Signals sustainability risk |

## Where this points

Cadence controls worth building into any serious setup:

- Work-packet templates for agent output.
- WIP limits for active runs.
- Checkpoint definitions by task type.
- Review-readiness criteria for agent-generated work.
- "Safe overnight work" and "requires live human" classifications.
- End-of-session handoff templates.
- Attention and review-load metrics.

A sprint-and-tracker model can evolve into a control surface for agentic cadence.

## Sources

- [Lisanne Bainbridge, Ironies of Automation](https://web.archive.org/web/20200717054958if_/https://www.ise.ncsu.edu/wp-content/uploads/2017/02/Bainbridge_1983_Automatica.pdf)
- [Google SRE Book: Eliminating Toil](https://sre.google/sre-book/eliminating-toil/)
- [Google SRE Book: Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Principles behind the Agile Manifesto](https://agilemanifesto.org/principles.html)
- [DORA Research: 2024 Accelerate State of DevOps Report](https://dora.dev/research/2024/dora-report/)
- [OpenAI Codex: Prompting](https://developers.openai.com/codex/prompting)
- [OpenAI Codex: Subagents](https://developers.openai.com/codex/subagents)
- [Model Context Protocol: Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)

---

*Previous: [Part 2 - Human Skill Changes](./02-human-skill-changes.md). Next: [Part 4 - Compounding and Equilibrium](./04-compounding-and-equilibrium.md). [Series index](./agentic-engineering.md).*
