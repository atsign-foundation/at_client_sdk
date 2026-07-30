# Template for per-package developer docs

**This file is the template, not a doc.** Copy it to
`packages/<package>/docs/<topic>.md`, delete this header section, and
fill in the rest.

Audience: a developer working on or against the package — including an
AI agent reading it before touching the code. `README.md` explains how to
*use* a package. `docs/` explains where a subsystem is *heading* and
which decisions got it there, so the next person doesn't reopen a settled
question or "fix" something deliberate.

## Authoring rules

1. **One topic per file**, named for the question it answers
   (`pkam-signing.md`, `atkeys-file-format.md`). Split rather than nest.
2. **Short.** If it runs past ~100 lines, it's restating the source. Link
   to the code instead; dartdoc is the place for per-method contracts.
3. **Decisions carry their reasoning, and their rejected alternative**
   where there was one. A decision without a why gets undone.
4. **Say what isn't done.** Half-finished migrations, deferred protocol
   questions, and known semver caveats are the highest-value content in
   the file, and the part nobody else will write down.
5. **Every section should stand alone.** Readers arrive from links and
   greps, not the top. Repeat the subject noun: "`FileAtKeysIo.write`
   throws…", not "it throws…".
6. **Present tense, no history.** Not "we recently changed" — the
   CHANGELOG covers what changed and when.
7. **Point at files; don't inline long snippets.** Snippets drift
   silently. One short usage snippet is worth it; a walkthrough is not.
8. **Cite real paths** — `lib/src/keys/io/file_io.dart`, not "the file IO
   class". Cross-package links are relative:
   `../../at_lookup/docs/pkam-signing.md`.
9. **Own the split when a change spans packages.** Each package's `docs/`
   covers its own side; state shared rationale once, in the package that
   owns the thing, and link from the other.
10. **Preserve domain capitalisation**: atsign, atServer, atKey,
    `.atKeys`, APKAM, PKAM, CRAM, Atsign Protocol.
11. **Update the doc in the PR that changes the code.** A stale doc here
    is worse than no doc, because it will be trusted.

---

<!-- ==== copy from here down ==== -->

# <Subsystem or feature> — direction and decisions

Status: <landed in \<package\> \<version\> | in progress | superseded by …>.
<Add "Migration incomplete." or similar if it applies.>

<If the change spans packages: one line naming what lives in the other
package, with a relative link to its doc.>

## Direction

<Where this subsystem is going and what problem that solves. Lead with
what was wrong with the previous shape — concretely, not "it was
messy". 2–3 short paragraphs.>

<Optional: the smallest snippet that shows the intended usage.>

## Decisions

**<The decision, as a claim.>** <Why. The alternative that was rejected
and what it would have cost. 2–4 sentences.>

**<Next decision.>** <Why.>

<Include decisions a reader might otherwise undo: deliberate throws,
intentional deprecation-over-removal, values that are load-bearing for
wire or file compatibility. Say plainly when something is a tripwire.>

## Not done yet

- <Unmigrated callers, and what their migration unblocks.>
- <Deferred questions and who has to answer them.>
- <Semver caveats — including ones the version bump understates.>

## Reference

- `lib/src/<path>.dart` — <what a reader finds there>
- `test/<path>_test.dart` — <what it pins down>
