# VFS / W4 live lab — results

**Date:** 2026-10-13 · **Browser:** Chromium 156.0.8078.4 (Playwright headless) unless stated ·
**Harness:** `packages/at_client_wasm/tool/vfs_lab/` (+ `tool/payload/measure.sh`) ·
**Plan:** `plans/2026-10-12-vfs-live-test.md` (local) · **Settles:** W4, P1 ([at_server#2754](https://github.com/atsign-foundation/at_server/issues/2754)), and amends [D-21](decisions.md) via [D-25](decisions.md).

## Verdict

| Question | Answer |
| --- | --- |
| W4 — is SQLite-wasm's payload acceptable? | **Yes.** +386 KB gz, fixed per app, not per record. Budget accepted; D4 (raw IndexedDB) is not triggered. |
| P1 — which VFS? | **`SimpleOpfsFileSystem`, one directory per (atSign, enrollmentId).** It is the only option that was clean on every axis tested. |
| D-21's table | **Two cells were wrong** (below). Its `WasmVfs` rejection stands. |

## Evidence

### E1 — payload (W4) · gz over the `remote_only` baseline, compare deltas only

| Variant | dart2wasm gz | dart2wasm br | dart2js gz |
| --- | --- | --- | --- |
| raw IndexedDB (D4) | +6.8 KB | +5.0 KB | +1.7 KB |
| SQLite-wasm bindings + minimal real-schema adapter | +38.3 KB | +33.7 KB | +27.3 KB |
| … plus `sqlite3.wasm` binary (347,931 B gz) | **+386.2 KB** | **+362.8 KB** | **+375.2 KB** |

Fixed first-load cost. Parse/compile time **not measured**.

### E2 — crash consistency · 200 runs/arm, `Page.crash` at 150–1500 ms, writing `at_data` + `commit_log` + counter per transaction

| Arm | clean | lost acked | torn | corrupt | unopenable | acked tx lost (median / p90 / max) |
| --- | --- | --- | --- | --- | --- | --- |
| IndexedDB, ack on commit | 0 | **200** | 0 | 0 | 0 | 42 / 73 / 155 |
| IndexedDB, ack after `await flush()` | **200** | 0 | 0 | 0 | 0 | 0 |
| SimpleOPFS | **200** | 0 | 0 | 0 | 0 | 0 |

- **D-21's "no crash consistency" is really "no durability until flushed".** Transactions stayed atomic in all 400 IndexedDB runs; what dies is the *unflushed tail*. Awaiting `IndexedDbFileSystem.flush()` before acknowledging closes it.
- **Cost of that flush:** ~35% fewer transactions in the same window (median acked 206 → 136). SimpleOPFS managed 63 — it is synchronous-durable per commit, so slower than either IndexedDB arm.
- **Fault model: a renderer kill only.** It does not model power loss, OS crash or a browser-process kill. Not tested; do not read it as proof against those.

### E3 — multi-atSign on SimpleOPFS · Chromium, WebKit, Firefox, Safari

| Scenario | Result |
| --- | --- |
| Two directories + distinct `vfsName` in one worker | Both open; row counts isolated (5 vs 3), integrity ok |
| One worker per database | Both open, independent |
| Same directory opened twice | Second open fails (`NoModificationAllowedError` on Chromium and Firefox; `InvalidStateError` on WebKit and Safari) |

D-21's "exactly two files" is true **per `SimpleOpfsFileSystem` instance**, not per origin. `loadFromStorage(path, vfsName:)` takes a directory and a VFS name, so one instance per (atSign, enrollmentId) is supported. Same-directory exclusion is a feature: it is a single-writer lock.

### E4 — open latency and size · Chromium; WebKit and Firefox beside it; 29.5 MB at 100k rows

| Rows | IndexedDB open | SimpleOPFS open | IndexedDB bulk flush |
| --- | --- | --- | --- |
| 1k | 26 ms | 13 ms | 33 ms |
| 10k | 43 ms | 13 ms | 77 ms |
| 100k | **178 ms** (WebKit 349, Firefox 176, Safari 350) | **13 ms** (WebKit 18, Firefox 23, Safari 18) | 586 ms (WebKit 1,322, Firefox 440, Safari 1,764) |

IndexedDB open grows with the database; SimpleOPFS open is flat. IndexedDB holds the whole file in memory (open cost tracks file size). Heap/RSS **not measured**.

### E5 — browsers

| Browser | E3 | E4 | E7 | E2 |
| --- | --- | --- | --- | --- |
| Chromium 156 | ✅ | ✅ | ✅ | ✅ |
| WebKit 27.2 (Playwright build, **not real Safari**) | ✅ | ✅ | not run | not run (CDP crash is Chromium-only) |
| Safari 27.0.1 (real, macOS) | ✅ | ✅ | ✅ SimpleOPFS: second tab refused (`InvalidStateError`), first tab's 306 commits intact, integrity ok. IndexedDB: **not recoverable**: the second tab never acked and the verify tab could not open the database within 60 s (a hang, not Chromium's explicit error) | not run |
| Firefox 157.0.1 (stock) | ✅ | ✅ | ✅ — IndexedDB: `integrity_check` fails, 112 torn rows after two writers; SimpleOPFS: second tab refused, data intact | not run (no `Page.crash` equivalent) |

Same verdict on all four engines wherever tested. **Gap:** Safari/Chrome on iOS and Android, and E2 outside Chromium.

Safari notes: driven by `tool/vfs_lab/crash/safari.mjs` (`open -a Safari` plus an injected reporting shim, since `safaridriver --enable` needs an admin password and `osascript` hangs on an Apple Events prompt). E3/E4/E7 all ran. The earlier "E7 inconclusive" runs were a harness bug of mine (an unclosed IIFE in the shim, so no tab ever reported), not Safari or the display. Caveat on the IndexedDB arm: the verify tab timed out rather than reporting `integrity_check`, so Safari shows the database was left unusable after two writers but not the exact damage (Chromium: unopenable; Firefox: 112 torn rows).

Firefox notes: Playwright's patched Firefox builds (1482, 1555) would not start here. Stock Firefox only starts through Launch Services (direct exec reports "Could not find profile folder"), so it was driven with geckodriver `--connect-existing` (`tool/vfs_lab/crash/ffdrive.mjs`). Navigating a tab away leaves its SimpleOPFS worker alive in the back/forward cache, still holding the access handles; the harness opens one tab per step and closes it. That is also a product point: a bfcache-parked tab can keep the lock (see "not settled").

### E6 — price of the SimpleOPFS worker hop · echo worker, no SQLite

`postMessage` round-trip: 0.016 ms (300 B) / 0.062 ms (64 KB) on Chromium; 0.044 / 0.062 ms on WebKit. Negligible next to a SQLite statement or a network call. The real cost of a worker is not latency but **where Dart runs**: D-19 keeps Dart on the main thread because `package:cryptography`'s WebCrypto gate dereferences `window`. So the worker hosts only SQLite, behind the already-async `AtKeyStore` boundary.

### E7 — two tabs, one database · both tabs writing with flush-on-ack, then killed

| VFS | Result |
| --- | --- |
| IndexedDB | **Database damaged afterwards** — Chromium: unopenable (`Invalid typed array length: -4096`); Firefox: opens but `integrity_check` fails with 112 torn rows. Likely cause (inferred, not isolated): the VFS keeps a per-tab in-memory copy of the file (`indexed_db.dart:23`), so two writers overwrite each other's pages. |
| SimpleOPFS | Second tab **refused cleanly** at open; first tab's database intact (283 commits, integrity ok). |

This is the sharpest result. Atomicity under a crash (E2) does not protect IndexedDB from a second tab; it needs a cross-tab lock (Web Locks) that SimpleOPFS gets from the browser.

## What this does not settle

- Power-loss / browser-process-kill durability (E2 models renderer death only).
- Mobile Safari/Chrome, and E2 outside Chromium.
- `sqlite3.wasm` parse/compile time; memory.
- A frozen or bfcache-parked tab still holding the SimpleOPFS lock: Firefox showed it does (above); whether the user-visible app handles it (`pagehide`/`pageshow` release and reacquire) needs its own test before V2 ships.
- Worker/main-thread wiring for the real `AtKeyStore` (this lab drives SQLite directly).

## Reproduce

```bash
cd packages/at_client_wasm
tool/vfs_lab/build.sh                              # site into build/vfs_lab
cd tool/vfs_lab/crash && npm i && npx playwright install chromium webkit
node e2.mjs --vfs indexedDb|simpleOpfs [--flush]   # E2
node e3.mjs · node e4.mjs --browser … · node e6.mjs · node e7.mjs --vfs …
# Firefox: launch stock Firefox via `open -n -a …/Firefox.app --args --headless --marionette --profile DIR`, then
GECKODRIVER=… node ffdrive.mjs
```

Raw per-run data: `build/vfs_lab/results/` (gitignored). Needs unsandboxed local port binding.
