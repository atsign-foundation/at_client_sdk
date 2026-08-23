# detail/acceptance.md — how section 14 got to where it is

The correction history behind
[`acceptance.md` section 14](../acceptance.md#14-test-harness--implverify-mapping).

The live section states the design. This file holds what it used to say and why
that changed, on the same principle as `detail/decisions.md`: a live document
carrying its own argument with itself becomes a thing readers learn to skim,
and a stranger cannot tell which paragraphs are current. Section 14 reached 473
lines with 13 correction markers before this split; a cold read found that the
one *unmarked* stale paragraph then read as the most current thing on the page,
precisely because everything genuinely current was annotated.

Nothing here is needed to act on the design. It is kept because each entry
records a way of being wrong that cost real time.

## The image-override gap, closed

Section 14 read that both packs pin `atsigncompany/virtualenv:vip`, that "no
work package delivers an image-override path", and asked for "an image-override
env var (e.g. `VE_IMAGE`) honoured by **both** `runLocal.sh` harnesses".

That env var exists and is called `VIRTUALENV_IMAGE`: both harnesses read it
and default to the locally built `at_virtual_env:local`, and CI runs against
`atsigncompany/virtualenv:dev_env` rather than `:vip`. The paragraph asked for
something already built, which is the shape a plan row takes when nobody
re-reads it after the work lands.

The one part of it still true, and kept in the live section: a green local run
does not imply CI parity, so check which image produced a result before citing
it.

## The corpus was measured over 2 packs when there are 4

The row read "**180** live test declarations across 65 files … a looser
`grep -o 'test('` gives 225 and an indentation-anchored one 224". All three
figures were scoped to `tests/at_functional_test` and `tests/at_end2end_test`
alone. `tests/at_onboarding_cli_functional_tests` and its `_proxy` sibling are
live packs too, and the CLI one builds clients from a `PqPosture` in two arms —
the best live evidence for UC-C1.6.

Across all 4 the strict matcher gives **194** and a multi-line-aware one
**247**. A separate error hid inside the same sentence: `tests/*/` is a depth-2
glob and counted 4 Dart packages where `find tests -name pubspec.yaml` finds 7,
missing `tests/pq_matrix/{current,published,scenario}` — the very packages the
pair grid's out-of-process arm depends on.

## The ledger's first version scored 28 instead of 62

The runner reports a grouped test as `"<group> <name>"` while a citation names
the test's own name, so a `startsWith` match silently missed every grouped test
— most of both unit suites.

It is worth keeping because of how plausible the wrong number was: the rows it
dropped were ones whose proof genuinely lives elsewhere, so the report read as
an ordinary coverage gap. It was caught only by asking why a file in a report
that *had* been supplied was still reading NOT-EXERCISED. A ledger that
under-reports would have justified building tests that already exist.

`packages/at_client/test/acceptance_ledger_test.dart` now pins that join in both
directions, mutation-proven: restoring `startsWith` reddens the grouped-test
case, and an always-true matcher reddens the two over-matching cases.

## The pqActive monitor blocker, and two wrong figures before the right one

Section 14 recorded that a posture-faithful pqActive cell "cannot notify yet",
citing `nskey_self_notify_live_test.dart:289`, and it was carried as a
prerequisite. Three measurements in sequence, each correcting the last:

1. **One run said it did not reproduce.** A false negative from a single
   sample, and it was one approval away from being committed as fact.
2. **Three runs said 6 of 30 pqActive monitors were silent.** That read as a
   posture defect and was the rig: it held every client open until it hit the
   atServer's `inbound_max_limit`, which the far-side log states outright as
   `Wrote stats to 12 monitor connections`. The failures were deterministically
   the 9th and 10th arm of every run rather than intermittent. The comparison
   was confounded twice over, since 3 control arms against 10 test arms meant
   the control never reached the iterations where the failure lived.
3. **Equal-length interleaved arms, connections released, across 2 fresh
   virtualenvs**: pqActive **16 of 18**, control **18 of 20**. Both arms fail
   alike with `AT0014` "the connection went away", so posture is not what
   distinguishes them.

A related hypothesis died on the way: that this and
[14.34](../implementation-plan.md#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)
were one problem. `NotificationServiceImpl` has built its Monitor with
`signingAlgoType: signingAlgoOf(atClient)` since 2026-08-10, before both
observations, so the monitor was never authenticating RSA for want of anything
setting its algorithm — and 14.34's `signingAlgo:rsa2048` monitor was the
**legacy** client's of the two live at the time, correctly RSA.

A second candidate died too: `signingAlgoOf` falls back to
`preference.signingAlgoType` (default `rsa2048`) whenever
`_resolveSigningAlgoFromKeyMaterial` records null, and that path throws nothing
and logs nothing. The probe showed the fallback firing on the **control** arm
only, where it is correct by design — a legacy enrollment holds no typed
authentication material.

⚠️ **The probe's own output labelled that control-arm null "this is the
defect".** The label was written before the run and was wrong. It is recorded
because a rig that prints a verdict will have that verdict quoted back as a
finding.

## The build order outlived both its reasons

The paragraph read: *"Arm 1 and the ledger first, both on the VE … Arms 3 and 4
follow once the monitor breakage is diagnosed."*

Both orderings were killed by work recorded in the same section — the ledger was
built, and the monitor breakage was measured away — and neither correction
touched the paragraph that had reasoned from them. It was also the only
*unmarked* stale paragraph among 13 correction markers, so a reader who had
learned to distrust the annotated text and trust the plain text would have
trusted the one thing that was wrong.

## `manifest.dart` was never a ledger prerequisite

Ruling 115 and the plan both listed moving `manifest.dart` from
`packages/at_client/test/` to `lib/` as something the ledger needed first. The
ledger was built without it: the runner's own `--file-reporter json:` output,
joined to the citations `provenIn` records, was sufficient, so nothing moved
into at_client's shipped surface and none of the 194 live tests changed.

The move still blocks the *in-pack rails* — each pack asserting its own
citations — which is a different thing wanting the same file. A prerequisite is
owed to a purpose rather than to a project, and this one lost the purpose it was
written for while keeping another.

## The pqActive measurement, in full

The prerequisite read "a posture-faithful pqActive cell cannot notify yet",
citing `nskey_self_notify_live_test.dart:289`. The settling run used
equal-length interleaved arms across 2 fresh virtualenvs, waiting 45s on each
client for any notification at all:

| Arm | Monitor received | Silent |
|-------------------------|-----------------:|-------:|
| `PqPosture.pqActive` | 16 of 18 | 2 |
| default (control) | 18 of 20 | 2 |

The arms genuinely differed in the thing varied — every pqActive client resolved
`SigningAlgoType.mldsa65`, every control client resolved null and fell back to
`rsa2048` — and the atServer's own log carries `signingAlgo:mldsa65`
authentications alongside `rsa2048` ones, so ML-DSA PKAM connections were made
and accepted.

⚠️ **The residual rate is the rig's, not the product's.** Both runs aborted on
`AT0014` before finishing, which is why the denominators are 18 and 20 rather
than 20 and 20; the probe builds 20 clients for one atSign in a single process,
which is not a shape production has; and it tested monitor *readiness*, not
end-to-end delivery. What it supports is the comparison between the arms, not
the absolute number.

Settling anything in this area needs the atServer's own log, which has no
near-side representation: copy it out with
`docker cp test-virtualenv-1:/apps/logs <dir>` **before** the teardown, since
`runLocal.sh` ends in `docker compose down`.

## Why the functional pack has no `paths:` allowlist

`tests/at_end2end_test` allowlists because its atSigns are long-lived and real,
so a test nobody listed must not be able to reach them; it pays for that with
the risk that an unlisted test silently never runs, which
`suite_manifest_test.dart` exists to catch.

The functional pack's virtualenv is created and thrown away per run, so an
allowlist would carry the same risk with none of the benefit. A bare run
executes every file, which is what CI does.

`test/pq_tag_test.dart` keeps the tag set honest instead: it re-derives which
files should carry the tag and fails naming any that do not, so a new PQ test
cannot sit outside the set the stage and matrix arms select on. Mutation-proven
— removing one tag reddens it with that filename — and it carries both controls,
a real PQ file and a real non-PQ one, so a broken matcher is distinguishable
from a clean pack.

## What the first CI run showed that offline validation could not

Dispatch `32643853854`, the first execution of the ledger's workflow wiring.
The three e2e and functional jobs went green and uploaded their reports. Two
findings, neither reachable by parsing the YAML:

- **The `unit_at_client` report is absent when that job fails early.** It died
  at the format gate, before the test step, so there was no file to upload;
  `if: always()` ran the upload and it warned rather than failing the job,
  which is the intended behaviour. A missing report means "that suite did not
  get as far as running", and the ledger renders its rows NOT-EXERCISED, which
  is true.
- **A matrixed job uploads once per leg.** `unit_at_client` and
  `functional_tests` both run on `dart-channel: [stable, beta]`, so each
  uploaded twice under one artifact name — harmless for storage, ambiguous for
  anything that later downloads by name. Both now carry
  `${{ matrix.dart-channel }}`. The YAML was correct; the duplicate exists only
  at run time.

That run also failed on something unrelated to the ledger: two newly added
files were not `dart format`-clean, and `packages/at_client`'s format gate
fails on files you ADD while `dart analyze` and a full 1519-test suite both
pass locally.

## A link sweep that reported 7 breaks, and there were none

Run 2026-08-23 over all `](target)` links in `docs/projects/pq/`. The naive
version reported **7 broken**; a code-span-aware one reports **0**.

Every one of the 7 sat inside backticks, in prose *about* link syntax — and 6
of them were in the passage of `detail/implementation-plan.md` that exists to
explain this exact failure, one of which reads "the literal
`](target#anchor)` that appears in prose". A checker that strips fenced blocks
but not inline code spans reads that as a link and reports it broken, and
"fixing" it corrupts the sentence.

Two remain flagged and both are explained rather than broken: the anchor in
`post-quantum-cryptography.md`, which is gitignored and reaches nobody; and one
in `implementation-plan.md` whose target heading contains an inline
`[#2085](https://…)` link — GitHub slugs the *rendered* text, so the link is
right and a slugger reading raw Markdown is wrong.

The residue worth keeping: **a Markdown link checker must strip inline code
spans, and its controls must include a backticked instance**, or its first
finding will be the documentation of its own bug. This one got as far as a
filed TODO row before the check was re-run properly.
