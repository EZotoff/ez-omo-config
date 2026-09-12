---
patch_id: "opencode--tui-session-directory-scope"
dependency: "opencode"
target_file: "packages/tui/src/context/sync.tsx, packages/tui/src/app.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-12"
dep_version: "1.18.5"
runtime_effective: false
runtime_effective_note: "Set after the v1.18.5 rebuild is installed and the live surface check passes: fresh `oa` TUI on ez-omo-config must (a) list only same-directory sessions and (b) NOT insert a foreign session that receives a synthetic session.updated via the API while the TUI is open. Until then this flag is false. NOTE: TUI-only patch — the binary swap is non-disruptive (mv+cp, no service restart); running TUIs keep the old code until relaunched."
upstream_issue: "none"
verification_pattern: "Limit session list to current directory"
verification_note: "String literal from the retitled app.toggle.session_directory_filter command — survives minification and is unique to this patch, but presence alone cannot prove the query/event-store behavior. The regression test (tests/regressions/020-session-directory-scope.sh) pins the source structure; ## Runtime Verification pins the behavior."
surfaces: "tui-interactive"
---

# OpenCode TUI session list scoped to the attach directory (shared-daemon fix)

## Problem

After switching from one `opencode serve` per project to a single shared daemon
(`opencode-interactive.service` on :3030, attached per terminal via the `oa` shell
function = `opencode attach http://127.0.0.1:3030 --dir "$PWD"`), every TUI's
session list (leader+l dialog, quick-switch slots, dialog fallback) showed sessions
from other directories: other projects' repos and — worst — every non-git directory
(`/tmp` scratch dirs, bench workspaces) lumped into the shared "global" project.

Two independent causes, both client-side in the TUI:

1. **Project-scoped list query.** `sessionListQuery()` sent either `scope=project`
   or a worktree-relative `path=` filter. Sessions are bucketed per project: git
   repos get their own project, but every non-git directory shares the single
   "global" project (verified live: `GET /project/current?directory=/home/ezotoff`
   → `{id: "global", worktree: "/"}`). At a repo root the relative path is `""`,
   which the server treats as "no path filter" — so even repo-root attaches got the
   whole project, and non-git attaches got everything non-git on the daemon.

2. **Unfiltered global event stream + unconditional store insert.** The TUI
   subscribes to the daemon's global `/event` endpoint, which re-broadcasts every
   event from every directory with NO filtering (server
   `packages/opencode/src/server/routes/instance/httpapi/handlers/global.ts`:
   `GlobalBus.on("event", ...)` → raw SSE). The `session.updated` handler in
   `packages/tui/src/context/sync.tsx` INSERTED any session it did not already know
   into the local store, regardless of the event's directory. Result: sessions
   active in other terminals materialized live in this TUI's list (with the
   dialog's cross-directory name badge), crossed project boundaries, and polluted
   quick-switch slots and the dialog's fallback store.

The existing `app.toggle.session_directory_filter` kv toggle did NOT help: both of
its modes were project-scoped (`{scope: "project"}` vs the path-subtree query).

## Patch Description

`packages/tui/src/context/sync.tsx` (commit `106ace2f7` on
`fix/link-click-v1.18.5-solidjs`):

1. `sessionListQuery()` now returns `{}` when
   `session_directory_filter_enabled` is on (default). The SDK v2 client sends
   `x-opencode-directory` on every request; with neither `scope` nor `path` in the
   query, the server's `Session.list` hits its exact-directory branch
   (`eq(SessionTable.directory, instance.directory)`). Server-side support already
   existed — verified live on the daemon before patching:
   - `GET /session?directory=/tmp&roots=true&limit=100&scope=project` → 100
     sessions across ~20 directories.
   - Same query WITHOUT `scope`/`path` → 0 (no session has directory exactly
     `/tmp`); with `directory=/tmp/opencode` → 62 sessions, all exactly
     `/tmp/opencode`.
   Toggling the filter off still returns `{scope: "project"}` (old project-wide
   behavior).

2. `session.updated` handler: before inserting an unknown session, drop the event
   when the directory filter is on AND the event's `directory` metadata differs
   from this TUI's `sdk.directory`. Updates to already-known sessions always apply;
   when `sdk.directory` is undefined (plain single-user TUI launches) the guard is
   inert, preserving old behavior.

`packages/tui/src/app.tsx`: toggle wording updated to match the new semantics —
filter on (default): "Limit session list to current directory" offered when off;
"Show sessions from all directories in project" offered when on.

Known remaining edge (deliberately out of scope): `permission.asked` /
`question.asked` from foreign sessions still enter `store.permission` /
`store.question` (keyed by sessionID, not listed anywhere; no dialog renders for
non-current sessions).

## Verification

Pattern (necessary, NOT sufficient):

```bash
grep -a -c "Limit session list to current directory" ~/.opencode/bin/opencode
# expect ≥ 1
```

Source structure is pinned by `tests/regressions/020-session-directory-scope.sh`
(paired `.kill.sh` proves detection). Server-side exact-directory filter behavior
is stock opencode v1.18.5 (no server patch) — probed live as documented above.

## Runtime Verification

1. Relaunch a TUI against the shared daemon with the NEW binary:
   `oa` from `/home/ezotoff/ez-omo-config` (or tmux-driven
   `opencode attach http://127.0.0.1:3030 --dir /home/ezotoff/ez-omo-config`).
2. Open the sessions dialog (leader+l). Expected: only sessions whose directory is
   exactly the attach dir. Regression signal: sessions badged with other directory
   names (e.g. `ez-omo-bench`, `/tmp/...`).
3. While that TUI is open, synthesize a foreign update via the API (needs basic
   auth from `~/.config/opencode/serve-interactive.env`):
   `curl -u "$USER:$PASS" -X PATCH "http://127.0.0.1:3030/session/<some-/tmp-session-id>?directory=/tmp" -H 'Content-Type: application/json' -d '{"title":"scope-probe"}'`
   — wait 2 s, reopen the dialog. Expected: no `scope-probe` entry. Regression
   signal: `scope-probe` appears in the list.
4. Quick-switch slots (ctrl+1..9) must not offer foreign sessions.
5. Toggle System → "Show sessions from all directories in project": list returns to
   project scope (toggle restores old behavior).

If the regression signal is observed → set `runtime_effective: false` and record it
in a ## Current Runtime Status section; do NOT bump dep_version.

## Reapply Instructions

1. `cd ~/src/opencode` — the fix lives as commit `106ace2f7` on
   `fix/link-click-v1.18.5-solidjs` (rebase onto the next release branch; the two
   hunks are in `packages/tui/src/context/sync.tsx` (`sessionListQuery` body,
   `session.updated` insert guard) and `packages/tui/src/app.tsx` (toggle title)).
2. `cd packages/opencode && OPENCODE_VERSION="$(~/.opencode/bin/opencode --version)" PATH=~/.bun/bin:$PATH bun run script/build.ts --single --skip-install --skip-embed-web-ui`
3. Backup: `cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.backup-<ver>-session-scope-<ts>`
4. Swap. This patch is TUI-ONLY — no server code changes — so the non-disruptive
   swap is: `mv ~/.opencode/bin/opencode ~/.opencode/bin/opencode.old-<ts> && cp
   packages/opencode/dist/opencode-linux-x64/bin/opencode ~/.opencode/bin/opencode
   && chmod +x ~/.opencode/bin/opencode`. Running servers/TUIs keep the old inode
   (old code) until restarted/relaunched; a full service restart per the standard
   procedure is optional and can ride the next `oa-restart`.
5. Relaunch TUIs and run the Runtime Verification steps.

## Durable Alternative

Upstream: make the TUI's `sessionListQuery` directory-scoped on shared daemons and
filter global-event store inserts by event directory (or give the global /event
endpoint a directory filter opt-in). Both changes are small and generally useful
for the multi-TUI/single-daemon deployment model; not yet filed.
