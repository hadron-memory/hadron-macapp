# Agent dev guide — hadron-macapp

This is a native macOS application for the Hadron platform.

## Use of Hadron

Hadron is this project's institutional memory — assume it covers things that aren't
obvious from code alone (past incidents, decisions whose rationale isn't in the code,
conventions baked into several places). Relevant memories:

- `hrn:memory:hadronmemory.com::hadron-macapp` — memory for the Hadron macOS app
- `hrn:memory:hadronmemory.com::dev` — findings, conventions, ops, tasks (the routing index)
- `hrn:memory:hadronmemory.com::specs` — product specs (loc-as-citation; `hadron spec …`)
- `hrn:memory:hadronmemory.com::hadron-server` — Hadron's server/backend
- `hrn:memory:hadronmemory.com::hadron-portal` — Hadron's web app

(1) **Query Hadron before reading project code.** For the topics, entities, and decision
areas in a request, run `hadron_find_nodes` first, then `hadron_get_node` on promising hits.
Cite node `loc` values when you reference what you found.

(2) Call `hadron_get_node` with `urn: "hrn:node:hadronmemory.com::dev::instructions"` to load
the project introduction (what Hadron is, URN grammar, the platform-specs corpus, core
architecture). Read it once per session.

(3) At the start of **every change** — before drafting a plan — call `hadron_get_node` with
`urn: "hrn:node:hadronmemory.com::dev::preflight"`. It's a symptom-to-pattern routing
index into the findings, conventions, and ops branches (portal-specific patterns live in
the `hadronmemory.com::hadron-portal` memory). Search both `::dev` and `::hadron-server`.

(4) When a non-obvious finding emerges — a convention you discovered, a gotcha you hit, a
node that turned out to be wrong — capture, fix, or delete it immediately via
`hadron_create_node` / `hadron_update_node` (don't batch to end-of-session; context decays).

(5) The **Hadron CLI is a superset of the MCP tools** — use it as needed, e.g.
`hadron node get hadronmemory.com::dev::preflight`, `hadron spec ls -m hadronmemory.com::specs`.
When referring a human to a node, link `https://hadronmemory.com/app/u/<URN>`.

Quick reference for AI agents working in this repo. Updated 2026-07-01.
