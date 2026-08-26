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
glob and counted 4 Dart packages where `find tests -name pubspec.yaml` found 7 at
the time, missing `tests/pq_matrix/{current,published,scenario}` — the very
packages the pair grid's out-of-process arm depends on. ⚠️ **The figure is 6
now**: `tests/pq_matrix/current` was deleted, and the lesson is the glob rather
than the number. Re-derive.

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
[14.34](implementation-plan.md#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)
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

## The citation audit — cluster A, 2026-08-26

The [acceptance audit](../implementation-plan.md#the-acceptance-audit) is the
judgement no rail can make: does the test a row cites actually establish what
the citation's `proves:` prose claims. This section is the running record.
**Cluster A is done (36 citations); B, C and G are not (109 remaining).**

**Method, and it is worth copying.** Enumerate with the suite's own recorder
rather than a regex over `provenIn(` — the call wraps in most files and a
matcher that misses a third of the corpus is how this project has been wrong
before:

```bash
cd packages/at_client && rm -f /tmp/cit.jsonl && \
  ACCEPTANCE_LEDGER=/tmp/cit.jsonl dart test test/acceptance --concurrency=1 >/dev/null
```

⛔ **`rm -f` first.** `provenIn` **appends**, so a stale file reads as roughly
twice the citations. Measured 2026-08-26: 284 records where the answer was 145,
and the doubling looked like a real property of the suite until one file was run
alone. The count agrees with `grep -c 'provenIn('` at **147 minus the 2
declarations in `proven_elsewhere.dart`**, which is the second derivation that
makes the enumeration trustworthy.

### F1 — the clause level is 9% adopted

**13 of 145 citations carry `clauses:`. The other 132 keep the old
all-or-nothing verdict.** Legal by design — `provenIn`'s dartdoc says omitting
it is not a failure and the ledger reports such a row as *unpinned* rather than
covered — but the live plan described clause pinning as though citations
generally did it. Corrected there in the same commit as this entry.

### F2 — UC-A4.5's central clause was unguarded — ✅ CLOSED 2026-08-26

The row's clause: *"Alice's configuration decides what `@alice` is a
**recipient** for and nothing about who she can send to."*

Its two citations are `pairwise_secret_sharing_test.dart` ("two ML-KEM-1024
clients exchange the no-hybrid construction") and `kem_selection_test.dart`
("the two KEMs are not interchangeable"). **Neither isolates the clause.** The
first has sender *and* recipient configured for ML-KEM; the default arms have
both on X-Wing. So the two arms vary the recipient's advertised KEM **and** the
sender's configuration together — the differential fault this project's own
rules name, where the arms must differ in the varied thing and in nothing else.
The second proves that a cross-KEM open fails, which is the row's *motivation*,
not its behaviour.

⚠️ **The property itself holds.** `CkManager` routes by the recipient's
advertisement — `ck_manager.dart:107` and `:169` both pass
`keyAlgo: advertised.alg` — and `NskeyProvider.encrypt` refuses when
`advertised.alg != keyAlgo` (`nskey_provider.dart:153`). So this is an
**unguarded property, not a false claim**, and the citation is not dishonest;
it is under-powered.

**Why it still matters:** a regression that passed the *sender's* configured
algorithm would leave both cited arms green — both-X-Wing and both-ML-KEM still
agree — and would surface only as that provider guard throwing, i.e. as two
atSigns unable to communicate. That is precisely the outcome the row rejects in
its own words: *"refusing would protect nothing."*

✅ **The arm was written the same day**, in
`packages/at_client/test/nskey_kem_selection_test.dart` — "the RECIPIENT
advertisement decides the conveyance provider, not the sender configuration" —
and UC-A4.5 now cites it first. One sender, configured for `ml-kem-1024`
throughout, sealing to two destinations that differ **only** in what they
advertise; the observable is the `cryptoProviderId` `CkManager` stamps on the
conveyance write. It reads
`[at/nskey/XWING/AES/GCM, at/nskey/MLKEM1024/AES/GCM]`.

**Two mutations, because the arm has two lines of defence.** Routing
`CkManager` by `context.atClient.getPreferences()!.keyEstablishmentAlgorithms
.first` instead of `advertised.alg` reddens it through the provider guard, and
the failure text is the production symptom itself: *"@bob:myapp advertises a
x-wing nskey, which at/nskey/MLKEM1024/AES/GCM cannot seal to"* — the "refusing
would protect nothing" outcome the row rejects. Separately, mutating the
**expectation** to `[mlKem, mlKem]` fails quoting the reason string, which
proves the assertion itself discriminates rather than being carried by the
throw.

⚠️ **The test name carries no apostrophe, deliberately.** `provenIn` matches
raw source with `source.contains("'$testName")`, so an escaped `\'` in a test
declaration can never match the runtime string a citation holds. The rail
caught this on the first attempt, which is the mechanism working.

⚠️ **`nskey_kem_selection_test.dart`'s existing "a provider will not seal to
the other KEM's advertisement" is NOT this arm** and was the nearest thing
before: it addresses a provider directly, bypassing the routing that is the
claim.

### F3 — about 8 citations rest on tests they do not pin

`provenIn` pins **one** test name, and the rail asserts that one still exists.
Some arguments rest on more: *"Paired with the negotiation arms in the same
group"* (UC-A4.5), *"asserted directly in `test/nskey_rotation_test.dart`"*
(UC-A5.3), *"pinned deterministically … by the revocation-guard group in
`test/pairwise_secret_sharing_test.dart`"* (UC-A5.2). Rename or delete a
supporting test and the citation stays green while its stated argument loses a
leg — the same silent decay `provenIn` exists to prevent, one level up.

**Bounded rather than guessed:** 3 of 145 name a *different file* in their
prose; a phrase scan (`paired with|in the same group|sibling|companion|…`, with
both controls proven) returns 12, of which several use "sibling" for a domain
object rather than a test. Call it **~8**, and re-derive rather than quoting it.

⚠️ **I first read this as systemic from three examples I happened to open, and
the measurement cut it to about 6%.** Worth recording because the impression
was wrong in the direction that would have justified redesigning the mechanism.

**The cheap fix, if it is wanted:** let `provenIn` take a list of supporting
paths it also asserts the existence of. That keeps one citation per row while
making every leg of its argument rot-detectable.

### C1 — four findings, three of them closed

Audited 2026-08-26. **24 citations.**

#### F4 — one posture axis was pinned by nothing at all — ✅ CLOSED

`PqPosture.keyEstablishmentAlgorithms` — what an atSign **advertises for others
to seal to it**, and therefore the algorithm of the encapsulation key minted at
its next mint — had no raw-literal pin for any posture.

**Proven by mutation, not suspected.** Changing
`PqPosture.pqActive.keyEstablishmentAlgorithms` from `[x-wing]` to
`[ml-kem-1024]` left the entire at_client suite — **1573 tests** — green, zero
failures. That is a hole in the family of pins whose stated job is to catch
exactly this: *"reading a value back through the type would follow an accidental
edit silently."*

⚠️ **Easy to believe it was covered, because its near-twin is.**
`sealsToKeyAlgorithms` has its own group and its own raw-literal pin across all
three stages. The two are one word apart and opposite in direction: that one is
what this client seals *to*; this one is what others seal to *this atSign*.

✅ Closed by `every released stage advertises the same key-establishment list`
in `test/pq_posture_test.dart`. The same mutation now reddens quoting the
reason string.

#### F5 — "all seven axes" was stale in six places — ✅ CLOSED

UC-C1.6's title, heading, THEN clause, the section intro, the scenario file's
dartdoc and its test name all said **seven**. `PqPosture` carries **9** final
fields; its own dartdoc enumerates **8** under "The axes"; and only **6** differ
between `legacy` and `pqActive`. Seven was none of the three.

**It was correct when written and falsified within hours.** `f22ec76e7` wrote
it; `824508719` — *"the sender-side algorithm list becomes a posture axis"* —
added the eighth the same day and swept no count. The number then sat in six
homes for a week. Replaced with "every axis" plus the derivation, rather than
with 8, because a number in six places is the defect.

#### F6 — UC-C1.4 read PROVEN while its axis reached no production caller — ✅ CLOSED

The row is *"the key-exchange axis: the posture names pq enrollment"*. Its three
citations proved the two ends — the posture carries the mode, and at_auth
honours a mode it is given — and nothing joined them. The scenario's own GIVEN
names the gap ("at_auth cannot read a preference, so the posture's value is
applied by whoever builds the request") and no citation covered that clause.
Until 2026-08-26 the only production caller that submits an app enrolment,
`at_onboarding_cli`, built the unnamed `AtEnrollmentRequest(...)` — hard-set to
`legacy`.

⚠️ **The catalogue's kind table marked this row `partial`, which is honest about
depth and says nothing about the axis being inert in production.** "Partial" is
not a warning; it reads as "covered enough".

✅ Closed by the fix in `at_onboarding_cli` and a citation to
`enroll_key_exchange_mode_test.dart`, which is that middle.

#### F7 — a scenario still described the pre-flip default — ✅ CLOSED

UC-C1.6's THEN ended *"A bare preference runs the legacy posture, byte-identical
to the pre-posture SDK."* True until the SDK default became `PqPosture.pqReady`
on 2026-08-26 — after which a bare preference means ML-DSA PKAM, namespace-key
seeding on, pq key exchange, and a startup retrofit with no opt-out. Corrected
in place with what it used to say.

### B1 — the cluster asserts only what a retrofit must NOT gain

Audited 2026-08-26 at gkc's direction, after a demo session hit a retrofitted
enrolment that could do nothing. **Two structural gaps, and the second is the
one that let a live defect through.**

#### F8 — every B1 assertion is a restriction

UC-B1.3, the scoped-retrofit row, asserts: a new enrollment id, `mldsa65`, NOT
fully privileged, the root untouched, no root private, cannot anchor itself.
Every one is about what the enrolment must not gain. UC-B1.1 and UC-B1.2 have
the same shape, with the privileged additions inverted.

**Nothing in the cluster asserts a retrofitted enrolment can still do its
job** — seed its namespace key, write into its namespace, be sealed to, read
what it could read before. An atSign that authenticates and can do nothing
satisfies every assertion in the cluster, and that is exactly what was
reported: no seeding, every send refused, unreachable as a recipient.

⚠️ **This generalises past B1** and is worth carrying as a review question:
*does this row assert a capability, or only a restriction?* A cluster of
restrictions cannot fail for "it gained nothing and can now do nothing".

#### F9 — no B1 test builds a fresh client from the retrofitted keyfile

UC-B1.1, B1.2 and B1.3 all perform their post-retrofit work on the client
`selfRetrofit` handed back: the same process that did the retrofit, holding an
`AtChops` it rebuilt in memory. **None of them ever re-resolves credentials
from the keyfile on disk**, which is precisely where a flat-versus-typed
selection goes wrong — the file now holds the original enrolment's RSA keypair
in the flat fields and the new enrolment's ML-DSA material under `enrollments`,
and something has to pick.

⚠️ **Predicted from outside this tree**, by a session with less information
than the tree contains, and confirmed by reading: `git grep AtClientImpl.create`
over that file returns nothing.

**An arm was written and reverted the same day.** It authenticated afresh from
the retrofitted keyfile and asserted the session came up as the retrofitted
enrolment; it went **red**, returning the legacy id. It was reverted rather
than shipped because the assertion may be wrong rather than the product:
`AtAuth.authenticate()` returning the legacy id looks intended, with
`_settleEnrollmentIdentity` re-pointing the client afterwards — and that only
runs under a PQ posture, which this file's harness refuses to build alongside
its legacy one. ⛔ **Do not re-add that assertion without settling what
`authenticate()` promises**; a red test on an undecided design is worse than
the gap.

⛔ **The defect itself was reproduced and fixed on 2026-08-26** — see [the
retrofit
section](../implementation-plan.md#a-retrofitted-enrolment-cannot-run-an-authenticated-verb)
for the mechanism. The reproduction landed in the **CLI functional pack**, where
`at_activate` runs for real: a third arm in `pq_native_enroll_test.dart` runs
`at_activate list` on a keyfile a real retrofit has moved.

⚠️ **What that closes is the defect, not this finding.** The gap this audit
names is that the pack already enrolled an RSA enrolment under the default
posture and asserted it authenticated — and stopped there. Authentication is the
one thing the defect did not break, because at_auth authenticates on its own
connection before the client exists. **An assertion that a live enrolment
authenticates proves nothing about whether it can do anything**, and that
pattern is not confined to the row this audit was reading. The design question
above — what `authenticate()` promises after a retrofit — is also still open.
