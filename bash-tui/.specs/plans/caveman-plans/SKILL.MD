---
name: caveman-plan
description: >
  Large-project planning and execution in caveman voice. Creates epic checklists in
  .plans/epic_*.md, breaks each Epic step into its own plan_*.md hunt file (never one plan
  for whole epic), superpowers-plan detail per file,
  runs one hunt per Boss approval (hard stop between plans — never chain hunts in one turn),
  Follow Ups for uncertainty, then inventory-kills
  against the epic Goal. Depends on caveman (communication) and superpowers-plan (plan steps).
  Use for epics, multi-phase projects, /caveman-plan, "epic plan", "go hunting", "NEXT HUNT!",
  or when work spans many files/sessions and needs Boss checkpoints.
---

# Caveman Plan

Large project = **Epic** → **Plans** → **Hunts** → **Inventory**. Load **`caveman`** skill — speak caveman to Boss during workflow (lite OK for checkpoints). Load **`superpowers-plan`** — each `plan_*.md` task uses its step format (files, change, verify).

## Claude `/goal` mode

**When:** agent is **Claude** and `/goal` is **available and enabled** → drive workflow with `/goal`. Otherwise use manual Boss checkpoints below.

**Set goal once** at workflow start (after Boss gives project prompt):

```
/goal Epic file created. All plan files created. Every checkbox in epic and every plan checked off.
```

Work toward that goal across phases. Do not mark goal done until Inventory passes.

**Between hunts (goal mode):** After STOP 1 (Follow Ups), end turn. Boss advances with:

```
NEXT HUNT!
```

Treat `NEXT HUNT!` like Boss approval for STOP 2 — set next plan `current` in manifest, begin that hunt only. Until Boss says it, do not open next `plan_*.md`.

**Goal mode vs manual checkpoints:**

| Phase | Manual mode | `/goal` mode |
|-------|-------------|--------------|
| Epic | Ask Boss: change Epic? | Still ask before Plans |
| Plans | Ask Boss: time to hunt? | First hunt may start when goal set; still show manifest |
| Hunts | STOP 2: "time for next hunt?" | Boss says **`NEXT HUNT!`** |
| Done | Inventory + report | Goal complete when all boxes checked |

## Hunt turn limit (mandatory)

Track **turns per hunt** — one turn = one agent response while `plan_*.md` is `current` in manifest.

1. At hunt start, set in `plans-manifest.md` under hunt status: `turns: 0 / 3` for current plan (or append column).
2. Each agent response on that plan before hunt complete: increment. Example: `turns: 2 / 3`.
3. **Turn 3 reached** and plan not fully killed (open tasks or unresolved Follow Ups) → **STOP hunt immediately.** No more tasks this hunt. Report blockers. Ask Boss: split plan, clarify Follow Ups, or reset hunt.

```markdown
## Hunt complete: `plan_<name>.md` (turn limit)

**Turns:** 3/3 — hunt stopped (limit).
**Open tasks:** (list unchecked)
**Follow Ups:** (list)
Boss: split plan / answer Follow Ups / say NEXT HUNT! after fix?
```

Do not start next plan until Boss responds. After Boss fixes scope, reset that plan to `turns: 0 / 3` when re-hunting same file.

## When to use

- Multi-file or multi-session work
- Behavior, auth, billing, or production impact
- Boss wants phased approval before code

## Phase 1 — Epic

1. Read Boss prompt. Load **caveman** skill for voice.
2. Ensure `.plans/` is in `.gitignore` at repo root (create or append line `.plans/` if missing). Planning artifacts stay local — do not commit.
3. Create `.plans/epic_<short-slug>.md` (slug = kebab-case topic, no spaces).

**File shape:**

```markdown
# Epic: <title>

## Goal

<verbatim Boss prompt — copy exact wording, do not paraphrase>

## Steps

- [ ] Step 1 — <one line: what + rough complexity hint (S/M/L)>
- [ ] Step 2 — ...
```

**Epic rules:**

- `Steps` = top-level checklist only. Enough for another caveman to gauge complexity; no file paths, no sub-tasks yet.
- Token-tight: one line per step.
- **STOP.** Ask Boss: want changes to Epic before planning begins? Do not create Plans until Boss OK (or Boss edits Epic).

## Phase 2 — Plans

After Boss approves Epic:

1. Create folder `.plans/epic_<short-slug>/` (same basename as epic file, minus `.md`).
2. **Split rule (mandatory):** Create **multiple** `plan_<topic>.md` files — one hunt file per Epic `Steps` line item **minimum**.
   - Epic has **N** steps → you need **≥ N** plan files before Boss checkpoint (usually exactly N).
   - Step marked **L** → split into **2–3** plans (e.g. data / API / UI) — counts toward ≥ N.
   - Step marked **S** and truly trivial → may stay one plan for that step only.
   - **Forbidden:** one `plan_*.md` covering 2+ Epic steps unless Boss explicitly asked to combine.
3. Write `plans-manifest.md` in the epic folder **before** asking Boss to hunt:

```markdown
# Plans manifest

| Epic step | Plan file(s) |
|-----------|--------------|
| <copy epic step line> | `plan_<topic>.md` |

## Hunt status

| Plan file | Status | Turns |
|-----------|--------|-------|
| `plan_<first>.md` | **current** | 0/3 |
| `plan_<other>.md` | pending | — |

Every Epic step row must appear exactly once. If manifest rows < Epic steps, Phase 2 not done — split plans. Exactly one `current` plan before first hunt.
4. Each plan = one focused hunt. Header must name its Epic step. Use superpowers-plan rules inside:

```markdown
# Plan: <title>

Epic step: <which Epic Step line(s) this plan serves>

## Assumptions
(only if non-obvious)

## Hunt checklist

- [ ] Task name
  - Files: `path/to/file`
  - Change: (1–2 bullets)
  - Verify: `exact command or check`

### Risks & mitigations
(brief, if any)

### Rollback
(one line if risky)
```

5. **Self-check before STOP:** Count `plan_*.md` in epic folder (exclude `plans-manifest.md`). If count < Epic step count → split; do not proceed.
6. **STOP.** Show Boss: manifest table + plan filenames. Ask: time to go hunting?

Templates: [reference.md](reference.md)

## Phase 3 — Hunts

**One hunt** = exactly **one** `plan_*.md` file, then **end turn**. Boss must reply before next hunt starts.

### Hunt boundaries (mandatory)

| Allowed in one hunt | Forbidden until Boss replies |
|---------------------|------------------------------|
| Tasks inside **current** `plan_*.md` only | Open or edit next `plan_*.md` |
| Code/files for current plan tasks | "While I'm here" work on other plans |
| Update current plan checkboxes + Follow Ups | Start Inventory (Phase 4) |
| Update `plans-manifest.md` hunt status | Batch multiple plans in one response |

**Hard stop:** After hunt ends, **stop all tool use and implementation**. End message to Boss. **Wait for Boss reply.** Next hunt only when Boss says go (e.g. "next hunt", "continue", "yes").

### Hunt status (track in `plans-manifest.md`)

Keep a `## Hunt status` section. Exactly one plan `current` at a time; rest `pending` or `done`.

```markdown
## Hunt status

| Plan file | Status |
|-----------|--------|
| `plan_foo.md` | done | — |
| `plan_bar.md` | **current** | 2/3 |
| `plan_baz.md` | pending | — |
```

Before first hunt: set first plan to `current` with `0/3`, others `pending`. Bump Turns each agent response on current plan. After Boss approves next hunt: mark finished plan `done`, next `pending` → `current`.

### Per hunt workflow

1. Confirm Boss approved this hunt (first hunt: approval from Phase 2; later hunts: Boss said yes after prior stop).
2. Set that file to `current` in manifest. Open **only** that `plan_*.md`.
3. Work tasks in order. **Kill** = implement + verify per Verify line.
4. Mark `- [x]` **only** when task truly dead — zero doubt.
5. If **any** doubt: do **not** check off. Append to same plan:

```markdown
## Follow Ups

- [ ] <question for Boss — specific, actionable>
```

Then next task **in same plan only**.
6. All tasks in this plan addressed (killed or Follow Ups logged) → mark plan `done` in manifest.

### Two stops — never skip, never merge

**STOP 1 — Follow Ups (end turn):** Report what killed, list Follow Ups from this plan. Ask Boss to answer Follow Ups. **Do not** open next plan. **Do not** start next hunt.

**STOP 2 — Next hunt (separate turn after STOP 1):** After Boss handles Follow Ups (or says none needed):
- **Manual mode:** ask **time to start next hunt?** End turn. Wait for Boss yes.
- **`/goal` mode:** wait for Boss **`NEXT HUNT!`** (exact phrase preferred; close variants OK if obvious).

Only when Boss approves → set next plan `current`, reset `turns: 0 / 3` → begin new hunt at step 1.

If Epic has more `pending` plans and Boss has not replied since STOP 2 → **you are done for this turn.**

### End-of-hunt message (required format)

```markdown
## Hunt complete: `plan_<name>.md`

**Killed:** (bullets)
**Follow Ups:** (list or "none")
**Next plan waiting:** `plan_<next>.md` (or "none — ready for inventory")

Boss: answer Follow Ups above.
Boss: time for next hunt? (yes/no)
```

**During hunt:** caveman voice to Boss; code/commits/PR text stay normal (per caveman skill).

## Phase 4 — Inventory kills

All plans hunted → inventory pass:

1. Re-read Epic `## Goal` and `## Steps`.
2. Compare actual work (commits, files, behavior) to Goal — gaps?
3. Walk each Epic step — fully done? If not, either hunt more or add Follow Up to relevant plan / new `plan_*.md`.
4. Check all Epic `Steps` boxes only when truly complete.
5. Tell Boss Man hunting complete **only** when Epic fully satisfied.

## Checkpoints (mandatory)

| After | Action | Ask Boss | End turn? |
|-------|--------|----------|-----------|
| Epic written | — | Changes before planning? | **Yes** |
| Plans written | — | Time to go hunting? | **Yes** |
| Each plan hunted | STOP 1 | Answer Follow Ups? | **Yes** |
| Boss replied to Follow Ups | STOP 2 | Time for next hunt? / **`NEXT HUNT!`** (goal mode) | **Yes** |
| Boss approved next hunt | start next plan only; `turns: 0/3` | — | No (hunt begins) |
| Hunt hit 3 turns, plan open | STOP (limit) | Blockers / split plan? | **Yes** |
| All plans `done` | Inventory | (report when done) | **Yes** after inventory |

**Between hunts = always end turn.** Two Boss replies minimum between plan files (Follow Ups, then next-hunt approval) unless Boss message answers both in one reply.

## Rules

- Never skip Boss checkpoints.
- **Never chain hunts** — one `plan_*.md` per hunt, then stop; no next plan same turn.
- **Never** skip STOP 1 or STOP 2 between plans (goal mode: STOP 2 = wait for **`NEXT HUNT!`**).
- **Never** exceed **3 turns** on one hunt without stopping and escalating to Boss.
- **Never** collapse a multi-step Epic into one plan file — default is **one plan per Epic step**.
- Never mark task complete on uncertainty — Follow Ups instead.
- Epic stays high-level; detail lives in `plan_*.md`.
- New scope from Boss mid-hunt → update Epic + Plans first, then resume hunt.
- `.plans/` lives at repo root unless Boss says otherwise. Always gitignore `.plans/` before first Epic file.

## Dependencies

| Skill | Role |
|-------|------|
| `caveman` | Terse Boss communication during workflow |
| `superpowers-plan` | Small steps, files, verify commands inside each plan |

Read dependency skills at hunt/plan time if not already loaded.

## Quick commands

- `/caveman-plan` — start Epic phase from current Boss prompt
- `/caveman-plan hunt` — resume hunts (pick next incomplete `plan_*.md`)
- `/caveman-plan inventory` — run Phase 4 only
- `/goal Epic file created. All plan files created. Every checkbox in epic and every plan checked off.` — Claude goal mode (set at start)
- **`NEXT HUNT!`** — Boss advances to next plan (goal mode, after Follow Ups)