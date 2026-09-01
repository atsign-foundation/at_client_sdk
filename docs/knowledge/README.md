# knowledge/ — reusable facts about the Atsign platform

**Status: started 2026-09-01.** [`sdk.md`](sdk.md) is the only file with content,
on the virtual-environment test harness; `protocol.md`, `at_client.md` and
`at_server.md` do not exist yet. (No count here on purpose — it would have two
homes and rot in this one: `grep -c '^### ' docs/knowledge/*.md`.) This file is the agreed plan, written
before the work so it survives a context compaction. Ruled with gkc 2026-08-20.

⚠️ **The rail described at the foot of this file is still unwritten**, so
nothing yet checks that a nugget's citation resolves. Until it exists, a nugget's
`Evidence` line is only as good as the session that wrote it.

## What this is for

Facts that are expensive to re-derive and easy to get wrong — the kind that cost
a session an hour and are then forgotten. Not tutorials, not architecture
overviews, not rules about how to work (those are `CLAUDE.md`'s job, and rules
about a *project's* state belong in that project's plan).

The test for whether something belongs here: **would a fresh session waste time,
or reach a wrong conclusion, without it?**

## Where it lives, and why here

`docs/knowledge/` in **at_client_sdk**, in git, reviewed, and guarded by a rail.

Considered and rejected: `~/dev/atsign/CLAUDE.md`, which is the natural-looking
home and is **not in any git repo** — nothing reviews it, nothing goes red when
it rots, and a fresh session reads it first. That is the same failure mode as
`~/.claude/`, and this project has been bitten by it repeatedly.

Facts about **other repos** live here too, because a fact learned while working
in one repo otherwise lands nowhere. The cost is that this repo stores claims
about code it does not contain, so every such nugget **must name the ref it was
read at** — a sibling checkout is usually on its own working branch, not trunk.

## The four subjects

| File | Covers |
|-----------------|--------------------------------------------------------|
| `protocol.md`   | The Atsign Protocol itself — verbs, key shapes, visibility, sync and notification semantics, what the atServer enforces |
| `at_client.md`  | The Dart `at_client` package: how it actually works, and the ugly bits |
| `at_server.md`  | The Dart atServer (`at_server` repo) — every nugget refs-tagged |
| `sdk.md`        | The wider `at_client_sdk` workspace: packages, release train, toolchain, test harnesses |

## Nugget format

One `###` heading per fact. The heading is the claim, stated so it can be
disagreed with.

```markdown
### AtSignLogger.root_level only affects loggers created after it is set
**Is:** each `AtSignLogger` wraps a `Logger.detached` and copies `_root_level`
into its own level once, in the constructor. A logger already built never
follows a later `root_level` change.
**Matters because:** raising the level after a client exists changes nothing,
and the resulting miss reads as "the code never logged that".
**Evidence:** `packages/at_utils/lib/src/logging/atsignlogger.dart:47-53,82-87`
**Checked:** `8cf542b97`, 2026-08-20
```

- **Is** — the fact, in one or two sentences.
- **Matters because** — the mistake it prevents. A nugget that cannot name one
  is an architecture note, and belongs elsewhere.
- **Evidence** — one bullet per citation, in the form below. Never "I recall".
- **Checked** — the commit it was verified at, and the date. For another repo:
  `at_server origin/trunk @ <sha>`.

### Evidence cites a PATTERN, not a line number

```markdown
**Evidence:**
- `.` -> `tests/at_functional_test/runLocal.sh` -> `VIRTUALENV_IMAGE:-at_virtual_env:local`
- `at_server@45846a7b` -> `tools/build_virtual_environment/ve/Dockerfile` -> `COPY ./contents /`
- `.` -> `tests/at_end2end_test/runLocal.sh` -> `docker build` x0
```

`repo -> path -> pattern`, each backtick-quoted. Repo is `.` for this one, or
`<name>@<ref>` for a sibling, read at that ref rather than from its working tree.
The pattern is a **literal substring**, not a regex. A trailing `xN` asserts an
exact count — `x0` makes an **absence** checkable, which is the claim this
project gets wrong most often.

⛔ **Line numbers were the original rule and they are the wrong instrument**
(changed 2026-09-01, gkc). Not because they rot — a path rots too — but because
of *how* they fail. A path that rots stops resolving and says so. A line number
that rots usually keeps resolving and now points at something unrelated, so it
reads as verified while being wrong, and no check can tell the difference. Two
citations written by this project had already rotted that way: issue #2161 cites
`at_onboarding_service_impl.dart:139`, which is `:120` on trunk and absent on the
spike; issue #2154 cites a file that does not exist. Only the second announced
itself.

A pattern cannot drift, because it has nothing to drift to: it re-derives the
location on every read and goes visibly empty when the code changes.

**Evidence that no rail can check** — a live daemon, a network call, a
working-tree observation — goes under a separate heading saying so, so the rail's
silence is not mistaken for coverage:

```markdown
**Evidence (not rail-checkable — live daemon):** `docker image inspect ...`
```

## The rail

`packages/at_client/test/acceptance/knowledge_test.dart` asserts that every
citation's **pattern still matches** its file — at the stated count where one is
given. It does **not** assert the claim is true; nothing can. What it catches is
code moving out from under a nugget.

⛔ **It also asserts its own corpus is non-empty** — nuggets found, citations
found, local citations checked. An empty enumeration reports "0 broken" and reads
exactly like a clean pass, and that is how this project has been fooled before.

Cross-repo citations are read with `git -C <sibling> show <ref>:<path>`, so they
are checked **at the ref the nugget names** rather than against whatever branch
the sibling happens to be on. Where the sibling is absent — CI, a fresh clone —
those citations are skipped, and the rail **prints how many it skipped** rather
than passing quietly. A skip is a gap in coverage, not a pass.

The existing `docs_structure_test.dart` is scoped to `docs/projects/pq` and is
the proven pattern to copy.

## Method, in order (gkc, 2026-08-20)

1. **Read the session transcripts** —
   `~/.claude/projects/-Users-gary-dev-atsign-repos-at-client-sdk/*.jsonl`
   (18 as of 2026-08-20). These carry facts that were established at cost and
   never written down anywhere else.
2. **Read this repo** — `at_client_sdk`.
3. **Read `~/dev/atsign/repos/at_server`** and
   **`~/dev/atsign/repos/at_services`**. ⚠️ Both are sibling checkouts on their
   own branches; name the ref for anything read there.
4. **Grill gkc** — one question per turn, with options, on what source cannot
   settle. Expect the corrections to be the valuable part.
5. **Then write** the nuggets and the rail.

⚠️ **Do not write nuggets before step 4.** The point of grilling is that a fact
I derive alone is a claim; a fact gkc corrects is knowledge. Writing first turns
the grilling into a review of my prose instead of an interrogation of the facts.

## Seed candidates from the 2026-08-20 session

Evidenced, not yet written up, and each still needs its citation re-checked:

- `AtSignLogger.root_level` copies at construction (above).
- `'data:null'` is the contract for reading an expired or not-yet-born record,
  not an error — 16 call sites depend on it.
- `public:_` keys are never synced; ordinary `_`-prefixed **self** keys are.
- `AtClientPreference.syncRegex` defaults to null, so the pull is unfiltered.
- Record immutability is enforced by the atServer on the `delete` verb; the
  client keystore has no immutability guard on remove.
- `DeleteVerbBuilder.force` emits `force:`; `:nc`/`noCommit` exists in
  at_commons and is implemented by no atServer.
- `Secondary.executeVerb`'s `sync` parameter is inert on both implementations.
- The keystore's `get()` does not filter expired records, and `nextExpiresAt()`
  has no cutoff where its sibling `nextAvailableAt()` does.
