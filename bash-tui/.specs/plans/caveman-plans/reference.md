# Caveman Plan — reference

## Gitignore

Before first Epic, add to repo root `.gitignore`:

```
.plans/
```

## Example layout

```
.plans/
├── epic_auth-refactor.md          # 4 Epic steps below
└── epic_auth-refactor/
    ├── plans-manifest.md          # required: step → plan mapping
    ├── plan_jwt-middleware.md     # Epic step 1
    ├── plan_session-store.md      # Epic step 2 (split from L step if needed)
    ├── plan_client-contract.md    # Epic step 3
    └── plan_rollout-flag.md       # Epic step 4
```

**Wrong (do not do):** 4 Epic steps + only `plan_everything.md` — invalid Phase 2.

## Example epic

```markdown
# Epic: Auth refactor

## Goal

Replace session cookies with JWT access + refresh tokens. Must not log users out during deploy. Mobile clients must keep working.

## Steps

- [ ] Middleware + token issue/refresh — M
- [ ] Session → JWT data migration — L
- [ ] Client + mobile contract update — M
- [ ] Rollout + feature flag — S
```

## Example plan (excerpt)

```markdown
# Plan: JWT middleware

Epic step: Middleware + token issue/refresh — M

## Hunt checklist

- [ ] Add refresh token table
  - Files: `migrations/20260519_refresh_tokens.sql`
  - Change: table + index on `user_id`
  - Verify: `psql -f migrations/... -c '\d refresh_tokens'`

- [ ] Issue endpoint
  - Files: `src/auth/tokens.ts`, `src/routes/auth.ts`
  - Change: POST `/auth/refresh` returns new access token
  - Verify: `curl -X POST localhost:3000/auth/refresh -d ...`

## Follow Ups

- [ ] Refresh TTL 7d or 30d? Boss decide before env prod.
```

## Claude `/goal` (when enabled)

Set at workflow start:

```
/goal Epic file created. All plan files created. Every checkbox in epic and every plan checked off.
```

Boss advances hunts with **`NEXT HUNT!`** after Follow Ups handled.

## Hunt turn limit

| Turns on current plan | Action |
|-------------------------|--------|
| 1–2 | Continue tasks in same plan |
| 3, plan not done | **Stop.** Report open tasks + Follow Ups. Wait for Boss. |

Track in manifest, e.g. `plan_bar.md` → `current (turn 2/3)`.

## Hunt state machine

```
Epic (Boss OK) → Plans (Boss OK hunt?) → ONE plan_*.md (current)
  → tasks: kill | Follow Up
  → STOP 1 + END TURN → Boss: Follow Ups?
  → STOP 2 + END TURN → Boss: next hunt? OR `NEXT HUNT!` (goal mode)
  → turn 3 & not done → STOP (limit) → Boss: unblock?
  → (Boss yes) → NEXT plan only — never skip stops
  → all plans done → Inventory → Boss: hunting complete
```

**Anti-pattern:** kill tasks in `plan_a.md` then immediately open `plan_b.md` same response — **invalid**.

## Example manifest with hunt status

```markdown
# Plans manifest

| Epic step | Plan file(s) |
|-----------|--------------|
| Middleware + token issue/refresh — M | `plan_jwt-middleware.md` |
| Session → JWT data migration — L | `plan_migration.md` |

## Hunt status

| Plan file | Status |
|-----------|--------|
| `plan_jwt-middleware.md` | done |
| `plan_migration.md` | **current** |
```

## Mapping plans to epic (mandatory)

| Epic steps | Minimum `plan_*.md` count |
|------------|----------------------------|
| N steps (any size mix) | **≥ N** (default: **1 plan file per step**) |
| 1 step, S | 1 plan |
| 1 step, L | 2–3 plans (layers) |
| N steps, includes L | N minimum, plus extra splits for each L step |

**Phase 2 gate:** `count(plan_*.md) >= count(Epic Steps)`. Update `plans-manifest.md` to prove coverage.

## Example manifest

```markdown
# Plans manifest

| Epic step | Plan file(s) |
|-----------|--------------|
| Middleware + token issue/refresh — M | `plan_jwt-middleware.md` |
| Session → JWT data migration — L | `plan_migration-schema.md`, `plan_migration-runbook.md` |
| Client + mobile contract update — M | `plan_client-contract.md` |
| Rollout + feature flag — S | `plan_rollout-flag.md` |
```

## Inventory checklist

- [ ] Epic `Goal` satisfied by shipped behavior
- [ ] Every Epic `Step` checked or explicitly deferred with Boss OK
- [ ] No open `Follow Ups` (or Boss waived)
- [ ] Verify commands from plans re-run clean on current branch