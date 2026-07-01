---
name: mapme
description: Regenerates a one-page architecture map of the project from the actual current code. Use when re-entering a project after time away, onboarding, or after big changes — "map the project", "how does this fit together", "update the architecture doc", "give me the lay of the land". Reads code, does not trust stale docs.
---

# Map me

A one-page "how this fits together" doc is what lets you re-enter a project cold.
This regenerates it from the code as it actually is now — not from whatever the old
doc claimed. Run it whenever the mental map has gone fuzzy.

## Steps
1. **Survey the structure.** List the top-level dirs and key files. Identify the entry
   points (main, app factory, CLI, server, the graph's compile/run for agent projects).
2. **Trace the main flows.** For the 1–3 primary use cases, follow execution: where a
   request/input enters, what it passes through, where it exits. Use the real call graph,
   not assumptions — grep/read to confirm.
3. **Identify the boundaries.** The modules and their responsibilities, what depends on what,
   and where the seams are (interfaces, adapters, external services, the DB).
4. **Write `docs/ARCHITECTURE.md`** with these sections, kept to one page:
   - **One-paragraph overview** — what the system does, top down.
   - **Entry points** — where execution starts, with file:line.
   - **Module map** — each module: one line on responsibility + key files.
   - **Main data flow** — the primary path, as a short numbered list or a simple
     text/mermaid diagram.
   - **External dependencies** — DBs, APIs, services, and what they're used for.
   - **Where the risk lives** — the 2–3 most complex or consequential spots.

## For graph/agent projects (e.g. LangGraph)
Also emit a mermaid diagram of the node/edge structure — the graph IS the system,
so a picture of nodes, edges, and conditional routing is the single most useful artifact.
Read the graph definition to get it right; don't sketch from memory.

## Guardrails
- Regenerate from code every time; never just reformat the existing doc.
- One page. If it's growing past that, link out to detail rather than inlining it.
- Flag anything you found that contradicts the previous ARCHITECTURE.md — drift is a signal.
