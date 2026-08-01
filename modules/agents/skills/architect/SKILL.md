---
name: architect
description: >
  System-level architecture for OMP /design and design discussions.
  Monolith/microservices/serverless, quality attributes, Arc42, ADRs.
  Load by path ~/.agents/skills/architect/SKILL.md — not cold skill://.
---

# Architect — OMP software architecture skill

Derived from
[vasilyu1983/AI-Agents-public `software-architecture-design`](https://github.com/vasilyu1983/AI-Agents-public/tree/main/frameworks/shared-skills/skills/software-architecture-design)
@ `6a223ba13c311c09b41c1dc09c14ab75e703894b`. See `UPSTREAM.md`.

Use for **system-level design** (boundaries, patterns, data, ops), not
single-service implementation details.

## OMP load contract

| | |
|--|--|
| **Path** | `~/.agents/skills/architect/SKILL.md` |
| **Cold catalog** | **Never** `skill://architect` (cold is intent-router+beads only) |
| **Missing skill** | Warn once; continue with brainstorming/ponytail only (**fail-open**) |
| **References** | Read on demand under this directory; do **not** paste bodies into agent prompts |
| **Install** | Nix agents activation copies this tree → `~/.agents/skills/architect/` |

## Design-flow phase map

| `/design` phase | This skill contributes |
|-----------------|------------------------|
| **Intake** | Quality attributes, constraints, non-goals, success metrics questions |
| **PDR** | Problem, QAs, 2–3 candidates + tradeoffs, scope limits, what NOT to build |
| **Arc42** | Context/containers/components guidance; mermaid/structurizr diagram picks |
| **ADR** | Decision drivers + options; emit **schema JSON only** — controller writes `docs/adr/` |

Augments Superpowers `brainstorming` on PDR/Arc42 writers. Does **not** replace it.
Never auto-starts `/harness`.

## Quick reference

| Task | Pattern / tool | Dig deeper |
|------|----------------|------------|
| Architecture style | Layered, modular monolith, microservices, event-driven, serverless | `references/modern-patterns.md` |
| Scale | LB, cache, shard, read replicas | `references/scalability-reliability-guide.md` |
| Resilience | Circuit breaker, retry, bulkhead, degradation | same |
| Service boundaries | DDD, bounded contexts | `assets/patterns/microservices-template.md` |
| Data consistency | ACID/BASE, CQRS, saga, event sourcing | `references/data-architecture-patterns.md` |
| Inter-service | API gateway, mesh, BFF | `references/api-gateway-service-mesh.md` |
| Migrate monolith | Strangler, DB split, shadow traffic | `references/migration-modernization-guide.md` |
| Human ADR template | MADR-style planning | `assets/planning/adr-template.md` |
| Blueprint | Service blueprint | `assets/planning/architecture-blueprint.md` |

## Decision tree (style)

```text
New system or major refactor
  ├─ Single team, evolving domain?
  │   ├─ Start simple → Modular monolith
  │   └─ Rapid iteration → Layered
  ├─ Multiple teams, clear bounded contexts?
  │   ├─ Independent deploy critical → Microservices
  │   └─ Shared data model → Modular monolith + modules
  ├─ Event-driven workflows?
  │   ├─ Async processing → EDA (Kafka/queues)
  │   └─ Complex sagas → Saga + event sourcing
  ├─ Variable load / pay-per-use → Serverless
  └─ Strong ACID → Monolith or modular monolith
```

**Defaults:** teams under 10 developers → modular monolith usually beats microservices ops cost.

## Output discipline

- Absorb references; **do not** cite internal filenames in user-facing PDR/Arc42 prose.
- Concrete technology picks (not only pattern names).
- Explicit **what NOT to build** / defer (YAGNI, ponytail).
- Team/ownership implications when relevant.
- Success metrics (deploy frequency, lead time, error rate, MTTR).
- Depth on 3–5 decisions that matter — not exhaustive essays.
- OMP ADR path: **JSON for adr-writer**; controller owns `docs/adr/NNNN-slug.md`.

## Workflow (system-level)

1. Clarify problem, non-goals, constraints, success metrics  
2. Capture quality attributes (availability, latency, throughput, durability, consistency, security, cost)  
3. Propose 2–3 candidates + tradeoffs  
4. Boundaries: contexts, ownership, APIs/events  
5. Data strategy  
6. Ops: SLOs, failure modes, observability, DR  
7. Scope limits: defer / buy vs build  
8. Decisive ADRs only  

## 2026 trends (on demand)

Only when asked about current trends: `references/architecture-trends-2026.md`,
`data/sources.json` (`platform_engineering_2026`, `optional_ai_architecture`).

## Navigation

Read **at most 2–3** references per question.

| Reference | When |
|-----------|------|
| `references/modern-patterns.md` | Pattern choice |
| `references/scalability-reliability-guide.md` | Scale / SRE |
| `references/data-architecture-patterns.md` | Cross-service data |
| `references/migration-modernization-guide.md` | Monolith split |
| `references/api-gateway-service-mesh.md` | Mesh / gateway |
| `references/operational-playbook.md` | Framing questions |
| `references/architecture-trends-2026.md` | Trends only |

Templates under `assets/planning/`, `assets/patterns/`, `assets/operations/`.
