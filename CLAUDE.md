# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OmaProw is a single-plugin repository: an Omarchy/Quickshell bar-widget plugin (`marcuspelo.omaprow`) that searches Prowlarr across every configured indexer, sorts/filters the results, and grabs releases (individually or in bulk) by pushing them to whatever download client(s) are already configured in Prowlarr. There is no build system, package manager, or test suite — the entire plugin is one QML file plus a manifest.

## Architecture

- **`Panel.qml`** is the whole plugin: bar chip, popup panel, all state, and all networking, organized into `// ---- <section>` blocks: `config`, `credentials`, `categories`, `search`, `sort`, `selection`, `grab`, `history`, `formatting`, `components`, `io`, `networking`, `lifecycle`, `bar chip`, `panel`.
- **`manifest.json`** declares the plugin id (`marcuspelo.omaprow`), entry point (`Panel.qml`), and three non-secret settings (`baseUrl`, `pageSize`, `defaultCategoryId`). The API key is never in this schema.
- **Networking**: every Prowlarr call goes through `curl` via `Quickshell.Io.Process`, never `XMLHttpRequest`. Each request `Process` declares `stdinEnabled: true` statically and writes `apiKeyHeaderConfig()` (`header = "X-Api-Key: ..."` as a `curl -K -` config line) in `onStarted`, then sets `stdinEnabled = false` right after `write()` — this is the exact pattern proven in `marcuspelo.omarqui`'s `statsProc`/`instancesProc`/`torrentsProc` (not the "imperative right before `running = true`" variant documented in `omatv`/`omalink` — both forms exist across this plugin family; this one follows `omarqui` since it's the closest structural sibling and ships working). Never add a new call that passes the API key via a URL or command-line argument.
- **Prowlarr's `downloadUrl` embeds the API key** as a plain query parameter in every search result (confirmed live: `?apikey=...&link=...`). This plugin never uses it — grabbing goes through `POST /api/v1/search` with `{guid, indexerId}` instead (the same endpoint Prowlarr's own web UI uses for its "Grab Release(s)" button), which needs no embedded key. Only `infoUrl` (the indexer's own release page, never key-bearing) is ever opened externally, via `openExternalUrl()`, which also guards against non-`http(s)` schemes.
- **Category ids are Prowlarr's real top-level category ids**, confirmed live against `/api/v1/indexer/categories`: `0` All, `1000` Consoles, `2000` Movies, `3000` Audio, `4000` PC, `5000` TV, `7000` Books. `6000` (XXX) and the two `Other` buckets (`0`/`8000` — `0` is reused here as the sentinel for "no category filter") are intentionally not offered, matching the original feature request.
- **Grab is a single-slot queue, not concurrent requests**: `grabQueue`/`grabbingGuid`/`currentGrab` drive one `grabProc` run at a time (`processGrabQueue()` pulls the next item in `handleGrabExit`'s `onExited`), because a `Process` can't run two overlapping commands. Both single-row grab and bulk "Grab Release(s)" push into the same queue. Per-row status (`grabStatus[guid]`: `"ok"`/`"error"`) is reset whenever a new search runs.
- **Grab success/failure is read from `curl -f`'s exit code**, not the response body — the exact shape of Prowlarr's grab response was deliberately never inspected live (doing so would have triggered a real grab as a side effect during development). If Prowlarr ever returns 200 with an in-body error for this endpoint, that would currently read as success — revisit if that turns out to be the case.
- **Sorting is client-side** (`sortedResults`, `sortKey`/`sortDir`) over whatever `performSearch()` last fetched — there's no server-side sort parameter in play, so re-sorting never re-hits the network. Column choice is a `Dropdown` + a direction-toggle button rather than clickable table headers, a deliberate deviation from Prowlarr's own web UI: this panel renders results as compact multi-line cards (title / meta / actions), not a literal spreadsheet table, because a bar-widget popup is too narrow for eight aligned columns plus a bulk-select checkbox.
- **Keyboard model**: `PanelKeyCatcher` reserves `h`/`j`/`k`/`l` (movement — unwired here; the results list is mouse/checkbox-driven, not cursor-driven), `Enter`/`Space` (activate), `x`/`X` (delete — unused, no delete concept in this plugin), and `Escape` (`closeRequested`, wired to `root.close()`). Everything else (`/` search focus, `g` grab selected, `r` refresh, `v` toggle Search/History) is handled in `onTextKey`, gated by `keyCatcher.blocked: searchField.activeFocus` so shortcuts don't fire while typing a query. The search `TextField`'s own `Keys.onEscapePressed` calls `keyCatcher.forceActiveFocus()` — **not** `root.close()` — matching the pattern documented in `omatv`/`omalink`: `PanelKeyCatcher.blocked` swallows all keys including Escape while a text field has focus, so without this the panel would be unclosable by keyboard whenever the search field was focused. Confirmed live during development (see Development loop below) that this exact bug existed before the fix.
- **History is Prowlarr's own `GET /api/v1/history`**, not a local cache — it includes every app hitting this Prowlarr instance (Sonarr/Lidarr RSS, etc.), not just grabs made from this plugin. `eventLabel()`/`eventColor()` map known `eventType` values (`indexerQuery`, `indexerRss`, `releaseGrabbed`, `indexerAuth`, `indexerQueryResult`) to short labels; unknown types fall back to the raw string. The `releaseGrabbed` → "Grabbed" mapping was confirmed correct against a real grab event already present in the live instance's history during development (not one this plugin caused).
- **Secrets on disk**: `API_KEY`/`URL_BASE` live in `~/.config/omaprow/.env` (parsed by a `FileView`, re-chmod'd to `0600` on every load) — never inside the plugin repo directory. This path is gitignored and must never be committed.

## Development loop

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/marcuspelo.omaprow"

omarchy plugin validate "$PLUGIN_DIR"
qmllint -I /usr/share/omarchy/shell "$PLUGIN_DIR"/*.qml

omarchy plugin enable marcuspelo.omaprow
omarchy-shell shell rescanPlugins     # picks up most edits
omarchy restart shell                  # use this instead if a logic-only edit doesn't visibly take effect

omarchy-shell marcuspelo.omaprow open  # open the panel via IPC (real keyboard focus, unlike `shell summon ... '{}'`)
```

There is no automated test suite. Verify changes with `omarchy plugin validate` + `qmllint` (must both pass clean), then a live check against the real Prowlarr instance: open the panel via the command above, drive it with `wtype` (keyboard-only; there is no `xdotool`/`ydotool` in this environment) for anything reachable via shortcuts, or ask the user to click for mouse-only interactions (category buttons, sort dropdown, checkboxes, Grab buttons — none of these have keyboard bindings), and screenshot with `omarchy capture screenshot fullscreen save` (get the widget's geometry first via `omarchy-shell shell debugBarGeometry`) to inspect the result.

- `wtype` sends keys to whatever window currently has compositor focus — it has no concept of a target window. Only send it immediately after a fresh `omarchy-shell marcuspelo.omaprow open` (which grants `keyCatcher` real focus via `onOpenedChanged`), and only right after taking a screenshot to confirm the panel is actually on-screen.
- `omarchy-shell shell rescanPlugins` does not reliably pick up logic-only edits (confirmed during this plugin's own development, matching the same note in `omalink`'s CLAUDE.md) — run `omarchy restart shell` if a live-tested behavior doesn't match what was just edited.
- **Never trigger a real grab during automated/agent-driven testing without the user's explicit go-ahead** — unlike every other action in this plugin, a grab is a real side effect on the user's actual download client (adds a torrent/NZB, starts a real download). Search and History are safe to exercise freely; Grab is not.

## Security notes specific to this plugin

- Every new network call must go through the same `apiKeyHeaderConfig()` + stdin pattern (see Architecture above) — no exceptions.
- Never build a request from a release's `downloadUrl` field — it carries the API key in plain text as a query parameter. Use `guid`/`indexerId` against `POST /api/v1/search` (the grab endpoint) instead.
- `openExternalUrl(url)` only ever hands `xdg-open` a URL matching `/^https?:\/\//i` — keep that guard if this function is touched, and never call it with anything but `infoUrl`.
- Any new file that persists a credential must be created at `0600` atomically (temp file + `umask 077` + `mv`), not written then `chmod`'d.
- `.env` must stay outside the plugin repo directory (`~/.config/omaprow/`, not `~/.config/omarchy/plugins/marcuspelo.omaprow/`) and stay in `.gitignore`.

## Git

- Not yet pushed to a remote or submitted to the marketplace as of this writing. When it is, follow the same flow as `omatv`/`omalink`/`omarqui`: SSH remote (`git@github.com:MarcusPelo/omaprow.git`), branch `main`, submission issue on `HANCORE-linux/omarchy-plugin-marketplace`, and HANCORE's pinned `security-scan.md` pre-submission checklist before submitting.
