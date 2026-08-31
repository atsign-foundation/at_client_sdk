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

Run 2026-08-23 over every Markdown link in `docs/projects/pq/`. The naive
version reported **7 broken**; a code-span-aware one reports **0**.

Every one of the 7 sat inside backticks, in prose *about* link syntax — and 6
of them were in the passage of `detail/implementation-plan.md` that exists to
explain this exact failure, one of which reads "the literal
any inline link target that appears in prose". A checker that strips fenced blocks
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

### Cluster B — started 2026-08-26, the enumeration and the first two findings

**Re-derived, both ways, after the enumeration moved.** The corpus stood at
**153** citations on 2026-08-26, not 147: UC-B1.4 to UC-B1.7 landed the same day
and brought six with them. The recorder and the regex agreed — 153 records, and
`git grep -c 'provenIn(' -- test/acceptance` summing to 155 minus the two
declarations in `proven_elsewhere.dart`. ⚠️ **Both figures are that day's, and
the corpus has grown a long way past them since** — every clause closed adds a
citation. Re-derive it rather than reading it here; this paragraph records how
the audit's enumeration was checked, not how many citations there are.

| cluster | citations | rows | audited |
| --- | --- | --- | --- |
| A | 37 | 20 | ✅ |
| C1 | 25 | 6 | ✅ |
| B | 42 | 25 | ✅ |
| G1 | 37 | 16 | ✅ |
| cross-cutting (no `UC-` id) | 20 | 6 scenarios of 10 | ✅ |

⚠️ **These are the counts AFTER the audit's own citations landed**, which is
why they do not match the figures in the finding bodies below: G1 was 35 and
cross-cutting 14 when they were read, and closing F13, F14 and F17 added 2 and
6. The rows sum to 161, which is the corpus — re-derive both, and `rm -f`
first.

⚠️ **Nothing remains: the audit finished on 2026-08-26**, every cluster plus
the cross-cutting bucket. This paragraph read *"the plan's `85 of 147` was
arithmetic over the pre-2026-08-26 corpus; against the tree today it is 91 of
153 remaining"* — both figures were correct when written and neither is a
statement about the tree now. Re-derive rather than quoting any of them; the
command is in the method above, and `rm -f` first.

**F-B1 — three rows are PROVEN and cite nothing live: UC-B3.1, UC-B3.2 and
UC-B5.2.** They produce **zero** records from the recorder. That is
legitimate under the catalogue's own definition — PROVEN means a scenario
asserts it and runs, not that a live test proves it — and
`b3_mixed_intra_test.dart` does assert, against a `MockAtClient`, that
`CryptoRuntime.providerIdFor` answers `legacyCryptoProviderId` for a
`readsNskeyWritesLegacy` config. What the row cannot show is the ladder
*behaving* that way against an atServer. UC-B5.2 is the same shape and better built — a `_RecordingProvider` pair with a
genuine control, asserting that provider routing is decided **per value** rather
than per client, so a namespace holding both eras at once decrypts each record
under the scheme it was written with. Against a mock.

⚠️ **A correction I owe, because I leaned on B5.2 earlier the same day.** When
deciding the shape of UC-B1.4–B1.7 I declined to add a row for "a retrofitted
enrolment still reads data written before the retrofit" on the grounds that
"UC-B5.2 already covers it". A row exists, and what it establishes is narrower
than I implied: per-value routing against a mock, not a live read of
pre-retrofit data by a retrofitted client. UC-B1.5 proves the live read half —
the retrofitted client writes and reads its own record against a real atServer —
but nothing proves the *pre*-retrofit half live. That gap is real and small, and
it is recorded here rather than turned into a row nobody asked for.

**Cluster B's evidence base, measured rather than assumed.** 42 citations across
25 cited rows, of 28 rows in the table:

| | rows |
| --- | --- |
| cited, with at least one LIVE citation | 22 |
| cited, resting **wholly** on unit citations | 3 — UC-B5.4, UC-B5.5, UC-B5.7, all `nskey_minting_test.dart` |
| not cited at all | 3 — UC-B3.1, UC-B3.2, UC-B5.2 |

34 of the 42 citations are live; UC-B4.3 and UC-B4.4 each carry one of each.
⛔ **None of this is a defect** — PROVEN means a scenario asserts it and runs,
and every one of these scenarios does. It is the number a reader counting
PROVEN cannot see: **22 of 28** B rows have live proof, not 28. ✅ **The
mint-lock rows were the ones worth a second look and they are sound** — see
F-B4: the interlock is split deliberately, and the atServer's half is pinned
live in a cross-cutting row those three never name.

**F-B2 — CLEARED, and worth recording as cleared.** UC-B3.1's assertion rests
on a claim about code the test does not touch: *"put and notify share this one
decision point, so this covers both"*. That is the shape that ships wrong — a
comment asserting what other code does. Checked: `providerIdFor` is named in
`lib/` by exactly two files, and the notify path is not one of them. It reaches
it through the wrapper — `CryptoRuntime.prepareWrite` calls it, and both
`notification_service_impl.dart:674` and
`notify_request_transformer.dart:35` call `prepareWrite`. The claim holds, and
it holds for a reason a symbol grep alone would have missed.

**F-B3 — UC-B0.1 states "No partial state on the server" unconditionally, and
its own second citation proves that is conditional.** The row's `Then` ends
"aborts cleanly, stays legacy, mints no PQ keys, logs why. No partial state on
the server." Four of those five are established by the first citation. The fifth
is not, and the same row's second citation is what shows it: *"a parent without
`__manage` cannot deny its own aborted request, and the refusal says so instead
of implying the server is clean"*. So a **scoped** parent aborts and leaves its
`pending` enrollment behind — one per retry.

⚠️ **The qualification exists, in the Impl/verify prose**: *"where it cannot (a
scoped parent has no `__manage`) the refusal says so"*. That is honest, and it
is in the wrong place — a reader auditing clauses reads the `Then`, and the
`Then` is unqualified. This is the shape the clause level exists to catch and
cannot: the row is PROVEN, both citations are accurate, and the sentence a
reader acts on still overclaims.

✅ **CLOSED the same day.** The clause now reads "No partial state on the
server — **for a parent that can deny its own aborted request**", with the
scoped case and the scenario that asserts it named beside it.

**B2.1 and B2.2 audited, no finding.** B2.2's three clauses are each covered,
including the cross-row citation that carries the open-window half. B2.1's
central claim — the lockout is the expiry cap and not a per-key delete — is
established the strong way, by the keypair being untouched and a sibling legacy
enrollment authenticating in the same run. Two minor clauses ride uncited: the
`enroll:revoke` alternative (covered by UC-A5.3, so a cross-reference rather
than a gap) and "must re-enroll", which nothing exercises. Neither is worth a
row; recorded so the next reader does not re-derive them.

**F-B4 — CLEARED, and the chain is worth writing down because B5.4's own
citations do not show it.** UC-B5.4's central clause is *"exactly one takes
it"*, and an interlock is precisely the mechanism a mock cannot refuse: a fake
that accepts everything makes its presence and its absence indistinguishable.
All three of B5.4's citations are unit, so the row looks unproven on the
interlock. It is not — the property is split across two harnesses on purpose:

| half | where | what it establishes |
| --- | --- | --- |
| the client asks for an immutable create | `nskey_minting_test.dart` (unit) | `c.verbs.first.metadata.immutable` is true, and `lockAlreadyHeld` models the refusal rather than asserting it |
| the atServer refuses a second one | `tests/at_functional_test/test/pq_signing_root_mint_lock_test.dart` (**live**) | named exception and message, a pre-clean so the FIRST take cannot be the refused one, a `finally` release, and a control — the same write accepted once released |

That live pin is on the **root** lock's record, not the nskey lock's. Different
key, same mechanism, and the refusal is a property of the atServer's immutable
handling rather than of a particular record — `nskey_records.dart` says so at
the nskey lock's own definition. One pin is therefore defensible, and it is a
cross-cutting citation, so B5.4 never names it.

**Nothing owed.** Recorded because a reader auditing B5.4 sees three unit
citations against a clause about a server refusal and would reasonably conclude
the interlock rests on a mock. It does not; the evidence is one row over.
UC-B5.5 and UC-B5.7 sit on the same chain — B5.5's "a lock key with no ttl is
refused outright" is the client-side guard, which a unit test is the right place
for.

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
dartdoc and its test name all said **seven**. As of that closure `PqPosture`
carried **9** final fields; its own dartdoc enumerated **8** under "The axes";
and only **6** differed
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

#### F9 — no B1 test builds a fresh client from the retrofitted keyfile — ✅ CLOSED 2026-08-26

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

⚠️ **What that closes is the defect. The finding is that the property is
per-ROUTE, and the catalogue could not say so.** The pack had already enrolled
an RSA enrolment under the default posture and asserted it authenticated — and
stopped there. Authentication is the one thing the defect did not break, because
at_auth authenticates on its own connection before the client exists.

⛔ **An assertion that a live enrolment authenticates proves nothing about
whether it can do anything.** Worse, the behaviour WAS proven — for the other
route. `self_enrollment_retrofit_live_test.dart` had a `selfRetrofit` client
running a verb, receiving over a monitor and signing envelopes, on a
`{buzz: rw}` scoped enrolment, since before the defect existed. So a reader
asking "is a retrofitted enrolment proven to work?" found yes, and it was true
of `selfRetrofit` and false of `AtClientImpl._settleEnrollmentIdentity` — the
route `at_activate` and every SDK consumer take.

**Closed 2026-08-26 by four rows that name the route**,
[UC-B1.4](../acceptance.md#84-uc-b14--a-retrofitted-scoped-enrollment-runs-an-authenticated-verb)
to
[UC-B1.7](../acceptance.md#87-uc-b17--holds-the-parent-enrollments-grants-verbatim):
runs a verb, reads and writes inside its namespace, is refused outside it, and
holds the parent's grants verbatim — with UC-B1.4 citing all three routes
explicitly so neither can be read as covering the other.

⚠️ **Still open from this audit:** B1.3's `nskey`-subset clause is stated in the
catalogue and established by no citation (recorded at the row); and the design
question above — what `authenticate()` promises after a retrofit — is undecided.

### G1 — the keyfile-and-wire cluster, audited 2026-08-26

The last of the four clusters. **35 citations across 16 rows, and every row in
the catalogue is cited** — G1 is the only cluster with no uncited row. Six
findings, four of them closed the same day.

⚠️ **The enumeration table above recorded 15 rows and there are 16.** It folded
`UC-G1.9a` into `UC-G1.9`; the two are separate rows with separate citations,
and the count is corrected in place. Re-derive rather than trusting either
figure — the recorder groups by the `UC-` id in each scenario name.

**What makes this cluster different from A, B and C1.** Every one of its rows
was rewritten on 2026-08-18, and three of the four keyfile rows were describing
code that had been deleted or reversed under them. That history shows in the
`proves:` prose, which is unusually careful: most citations here say what the
row used to claim and why the old wording would have been proven backwards. The
audit's job in a cluster like that is not to find careless prose. It is to ask
whether the corrections have themselves gone stale, and one of them had.

#### F10 — UC-G1.4 refused an empty `keys` array in the catalogue and accepted it everywhere else — ✅ CLOSED

The row's *Then* read *"A `version: 1` document carrying a top-level `keys`
array is **refused by name**, not read as legacy"*, unqualified, and its own
⚠️ correction note said `AtKeys.fromJson` throws on `containsKey('keys')`,
*"empty array included"*.

`262b5f597` (2026-08-22) narrowed that throw to a **non-empty** array:

```dart
if (legacyKeys is! List || legacyKeys.isNotEmpty) { throw ... }
```

So the row had been false for four days, and the correction note was false in
the same breath as asserting itself. Both the scenario in
`g1_keyfile_test.dart` and the citation on the test say the right thing —
*"an EMPTY keys array is accepted, because that is what shipped"* — because
they were rewritten in that commit and the catalogue row was not.

**Why it matters more than a stale sentence.** The empty array is the shape
every released build wrote: that version never populated it, since `addKey` has
no caller outside `AtKeys` itself there. A reader working from the catalogue
would restore the blanket refusal and strand every keyfile a release had ever
produced, to guard an array carrying nothing.

Corrected in place, with what the row used to say and both directions it was
wrong in.

#### F11 — every refusal in the `enroll:update` cluster is `throwsA(isA<Object>())` — ✅ CLOSED 2026-08-26

`tests/at_functional_test/test/enroll_update_live_test.dart` carries seven
refusal assertions across UC-G1.11, UC-G1.12 and UC-G1.13, and **all seven
match any throw at all** — a connection reset, a timeout, a malformed command,
a server-side crash. Nothing distinguishes the guard firing from the call
failing.

⛔ **UC-G1.12's row forbids exactly this in its own words**: *"the atServer
refuses it by its own named error, not by 'it failed' — this is the
privilege-escalation guard."* The test's comment restates the requirement
faithfully and the assertion under it is `throwsA(isA<Object>())`:

```dart
// ... refused by its own error rather than by a generic failure, because
// this is the privilege-escalation guard and "it failed" would not
// distinguish it from a typo.
await expectLater(
    lookupOf(client).executeCommand(raw, auth: true), throwsA(isA<Object>()),
```

The comment is the specification and the assertion does not meet it.
`at_keys_test.dart` gets the same job right two packages away, asserting on
`e.message` with a reason saying why a bare throw would not do.

**In fairness to the tests, the arms around the assertions are good.** UC-G1.11
signs its wrong-key proof with the production helper, so it is a well-formed
proof over the right bytes; UC-G1.13 runs two genuine enrollments plus the
owner's connection; both carry a control showing the same request succeeds when
the guard should not fire. Those controls rule out *"a server that says no to
everything"*. What they cannot rule out is a transport failure on the refusal
arm specifically, since the control is a different call made later.

**Closed by probing first, then asserting.** All five refusals come back as
`AtLookUpException` with a distinct message, measured against a live
virtualenv rather than inferred from the handler:

| arm | code | message fragment now asserted |
| --- | --- | --- |
| G1.11 no signature | AT0011 | `requires apkamPublicKeySignature` |
| G1.11 wrong key | AT0011 | `does not verify against the apkamPublicKey being installed` |
| G1.12 escalation | AT0022 | `cannot change namespaces` |
| G1.13 other enrollment | AT0011 | `self-only`, naming **both** enrollment ids |
| G1.13 owner connection | AT0011 | `self-only … authenticated as the owner` |

The control — the same request on its own connection — succeeds, so every row
above is a refusal rather than a broken rig.

**Each assertion was then mutated, and each reddened quoting its own reason.**
Arm 2's expectation set to arm 1's message reddens, which is what proves the
two arms are refused by *different* checks: under `isA<Object>()` they were one
measurement, and a server that merely checked the field was present would have
satisfied both.

#### F12 — UC-G1.11's "and the record is unchanged" is asserted by nothing — ✅ CLOSED 2026-08-26

The row's *Then* is *"the atServer refuses **and the record is unchanged**"*.
UC-G1.12 asserts its half of that, comparing `namespace` before and after.
UC-G1.11 never fetches the record at all — `before` is not captured in the
test — so a server that refused the rekey *after* writing it would pass.

It is the sharper half of the two, because a partial write here installs a key
whose private half the caller may not hold, and the row's own request dartdoc
calls that outcome *"the emergency it is"*.

**Closed.** Asserted where it shows rather than where it is stored, because
`enroll:fetch` returns five fields and `apkamPublicKey` is not among them: the
key that authenticated before still does, and the key both refusals carried
does not. It sits before the valid-proof control, which rewrites the record
deliberately. Mutating the second half to `isTrue` reddens on its own
assertion.

#### F18 — UC-G1.12 was green for the wrong reason, and the guard it names was never reached — ✅ CLOSED 2026-08-26

**Found while closing [F11](#f11--every-refusal-in-the-enrollupdate-cluster-is-throwsaisaobject---closed-2026-08-26), and it is the more serious of the two.** F11 says
the assertion was too weak to tell the guard from a timeout. This says the
assertion was checking a refusal that had nothing to do with the guard.

UC-G1.12's server arm sent `enroll:update` naming `namespaces` **and nothing
else**. Measured live:

```
AT0022 · enroll:update must name at least one of apkamPublicKey, signingAlgo,
         apsk, apskLegacy or metadata
```

That is "you named nothing I recognise". The arm varied **two things at once** —
it added `namespaces` *and* omitted every field the verb knows — so it could not
distinguish *namespaces is refused* from *namespaces is ignored and the command
was empty*, which is the whole question the row exists to settle.

**The guard is real, and naming one valid field alongside reaches it:**

```
AT0022 · enroll:update cannot change namespaces: an enrollment amending itself
         must not be able to widen its own grant
```

⛔ **Proven by mutation, both directions.** Reverting the request to the
namespaces-only form while keeping the `cannot change namespaces` expectation
reddens, and the failure quotes the *other* message — so the arm as it stood
before today never reached the escalation guard, and deleting that guard
outright would have left it green. The catalogue row was right about the
mechanism the whole time; nothing was exercising it.

Both refusals are now pinned as separate arms, so a change collapsing them into
one message goes red.

⚠️ **The shape, and it generalises well past this row:** *a refusal arm must
differ from the accepted case in the forbidden thing and in nothing else.*
Stripping a request down to only the illegal field is the natural way to write
the test and the reliable way to miss the guard — an earlier well-formedness
check answers first, and its refusal is indistinguishable from the one you
meant. It is the differential-test rule wearing a refusal's clothing.

#### F13 — UC-G1.9's title clause was cited under UC-G1.8 — ✅ CLOSED

The row is called *"a retired algorithm still verifies history"* and its two
citations covered the transition and the retained advertisement. The test that
proves an envelope of the retired algorithm still verifies —
`signing_key_minting_test.dart`, *"an envelope signed before the withdrawal
still verifies"* — was cited under **UC-G1.8**, one row above.

Nothing was unproven; it was unfindable from the row that names it, which is
the whole complaint the audit exists to answer. Cited under UC-G1.9 as well,
which seven other tests in the corpus already do for their own second row.

#### F14 — UC-G1.9a's `enroll:update` branch rested on no citation — ✅ CLOSED

The row's *Then* names two advertisement branches: *"by `enroll:update` where
there is an enrollment record and by publishing `_apsk` directly where there is
not"*. The second is cited explicitly. The first was not.

The trap is a test name. *"mints, advertises and files the algorithm the set
names"* reads as covering it, and its assertions are `mint()`, `heldKeyIds()`
and the keyfile — `heldKeyIds()` reads the **keyfile**, not the advertisement.
Its `proves:` prose was honest about that all along: *"the mint itself, and
that the key reaches the keyfile."* So the row led with a branch its own
citations disclaimed, while two tests six lines away asserted it.

Closed by citing *"the advertisement names the minted key and drops the auth
key"*, which asserts the update carries the minted key and no longer carries
the APKAM authentication key.

⚠️ **Worth carrying as a review question**: *does the test's NAME cover the
clause, or do its assertions?* A name written aspirationally is the cheapest
way for a citation to look sound.

#### F15 — UC-G1.2's resolver clause is asserted by nothing

The row's *Then* ends *"and UC-G1.1's resolver returns the new enrollment id"*.
The single citation covers the byte-identical flat fields and the typed
material; `resolveAuthenticatingEnrollment()` is never called in it, and the
scenario in `g1_keyfile_test.dart` drops the clause silently rather than
restating it.

The clause is almost certainly true — after the retrofit exactly one typed
`privateAuthentication` is active, and the resolver returns the single
candidate — but it is a one-line assertion in a test that already holds the
retrofitted keyfile, so there is no reason for it to rest on an inference.

⚠️ **And the flat `enrollmentId` stays at the legacy enrolment**, which is what
makes the clause worth asserting rather than assuming: the file answers the
question two different ways depending on which field a reader takes, and the
row promises one of them.

#### What the cluster got right, since a finding list reads as an indictment

UC-G1.10 is the strongest row in the catalogue. It asserts the new key
authenticates *and* the old one no longer does, before checking what did not
move, so a server that accepted the request and did nothing fails rather than
passes. It explains why the rotation is checked where it shows rather than
where it is stored — `enroll:fetch` returns five fields and `apkamPublicKey` is
not among them. And it compares `_apsk` by **key** rather than by spelling,
because the record has a second writer: the client's own start-time heal path
republishes a lone `rsa2048` key in the bare form, so an array written at
approval becomes a bare string moments later, and which spelling is on the
record at any instant is a race with startup rather than anything the rekey
did.

UC-G1.14 and UC-G1.15 both name what they do not prove. G1.14 says outright
that the fail-closed half rests on an observation from a discarded draft and is
not separately proven; G1.15 records that mutating `pqActive` to resolve as
`pqReady` leaves all nine cells green, so the algorithm assertion is the only
thing discriminating. Neither needed a finding, and both would have earned one
without those sentences.

### The cross-cutting bucket — audited 2026-08-26, and nothing had looked at it

**14 citations across 6 of the 10 cross-cutting scenarios**, and the enumeration
table above carried them as `—` from the day it was built. Not deferred and not
declined: the audit was scoped cluster by cluster on the `UC-` ids, and a
scenario with no id belongs to no cluster, so the bucket fell between the
passes. The plan's own wording is *"read **every scenario's** `proves:` prose
against the test it cites"*, which includes them.

⚠️ **The shape to carry forward: an audit organised by the ids in a catalogue
cannot see work that has no id.** Four clusters were audited, each one finished,
and the denominator they were measured against was never the corpus.

These are the best-written scenarios in the suite. `reads are universal` is a
differential with a control and asserts the failure message names both the
missing provider id and the registered set; `performance is measured, not
assumed` runs `dart analyze benchmark` inside the assertion, because existence
plus four identifiers cannot tell a working harness from a broken one — which is
how the bench sat with five compile errors for six days. Two findings, and one
of them is the corpus's largest legibility gap.

**Examined and NOT a finding, recorded so it is not re-derived.**
`appMetadata.providerId is authoritative on keys and frames` delegates its
"and frames" half to `architecture_guard_test.dart` in a comment rather than a
`provenIn`, which looks like the same defect as F17. It is not:
`architecture_guard_test.dart` lives in `test/acceptance/` and is a scenario of
this suite rather than a test elsewhere, so there is nothing for a citation to
point at. The comment is the right shape — it says the property is one of the
SOURCE rather than of a run, which is why a rename breaking its grep reports a
broken guard instead of a failed scenario.

#### F16 — the nskey mint lock's refusal is proven for the *other* lock

`neither key record is immutable; the lock that mints them is` names two locks:
`_rootlock@owner` and `_nskeylock.<ns>@owner`. Its three citations prove the
signing root's metadata is mutable, prove the second `_rootlock` create is
refused **with the immutability error** and succeeds once released, and prove
the published nskey is mutable across a re-mint.

**None of them is about `_nskeylock`.** `pq_signing_root_mint_lock_test.dart`
holds exactly three tests and all three are cited, so there is no uncited arm to
point at. What covers the nskey lock instead is a raw-literal pin of the client's
*intent* — `wire_literal_pins_test.dart` pins the name, the immutable flag and
the two-minute ttl — and a mock in `nskey_minting_test.dart` that models the
refusal by matching on the key name:

```dart
if (builder.atKey.key == '_nskeylock' && lockAlreadyHeld) { ... }
```

⛔ **A mock cannot test a refusal it does not model, and the test is green
either way.** The mechanism here *is* the atServer saying no to a second
immutable create; a fake that returns whatever the test arranged makes the
guard's presence and its absence indistinguishable. The `_rootlock` arm shows
the live refusal exists on that record; nothing carries it across to the other.

**Cheap to close, and it is the same rig**: `pq_signing_root_mint_lock_test.dart`
already takes a lock against a live atServer, releases it and re-takes it. A
fourth test doing that with `nskeyMintLockKey` is the same shape against a
different key.

⚠️ **It touches the seeding failure mode.** [A client that exits during its
startup tail abandons seeding](../implementation-plan.md#a-client-that-exits-during-its-startup-tail-abandons-seeding)
described the self-perpetuating interlock as *"reasoned from the code, not
measured"* — a short-lived client that dies after the lock lands leaves an
immutable key with a 120-second ttl that nothing deletes, and a successor that
finds it held with nothing published throws rather than minting. ⚠️ **The
in-process half was measured on 2026-08-28** (`mint_lock_self_contention_test.dart`),
so what is left here is the LIVE citation, not the measurement. The 120 seconds
still describes `_nskeylock`; the signing root's own lock dropped to 15 seconds
under [ruling 124](decisions.md#124-the-signing-roots-mint-lock-is-sized-against-starvation-not-contention-2026-08-28).

#### F17 — the security clause of `advertised recipient keys are signed and verified` was described, not cited — ✅ CLOSED

The scenario claims *"A tampered, unsigned, or wrong-signer advertised key is
**REJECTED**"* and then says, in a comment, *"Both halves hold today at unit
level — `published_nskey_key_ring_test` and `key_package_registration_test`
cover the rejections"*. It names neither test. Its three citations are all about
the atServer side — `_apsk` fetchable without a client publish, a
cross-enrollment overwrite refused, a live `enroll:listns`.

**Measured: 16 of the 17 rejection-shaped tests across those two files are cited
by nothing**, including every shape the clause names — `an advertisement signed
by another atSign is rejected`, `a tampered advertisement is rejected`, `an
unsigned advertisement is rejected, not accepted bare`, and their key-package
counterparts. The one cited exception is about a package naming no suites, cited
from a cluster A row for a different reason.

So the one clause in this scenario that is a security guarantee was the one
clause a reader could find no evidence for, while ten well-built tests asserted
it two directories away. **The tests were never the gap. The ledger could not
see them, and this audit exists precisely because a reader cannot either.**

Closed by citing all six — three shapes on each half — and by replacing the
comment that described the coverage with the citations that carry it. The
verification rail was proven positive on the way in: mistyping one cited name
reddens the suite with a message quoting the citation and its `proves:` prose.

⚠️ **Generalises past this row**: *a comment naming a test file is not a
citation.* It reads like one, it is usually true, and the ledger — the artefact
this whole gate exists to produce — counts none of it.

## The clause burn-down — what each clause needs

Measured 2026-08-27 by reading every clause against the tree. **Every clause has
something exercising it; none is untested** — the single absence the mapping
found was refuted.

⛔ **No totals here.** This paragraph carried "91 are established as written, 44
are partial" while the tables four lines below said 35 and the tree said 99
proven of 135 — three figures for one quantity, in one file, and a wrap-up sweep
walked past two of them. The live figures come from the suite, which prints
`BURN-DOWN` on every run and has a guard that fails in both directions if the
recorded counts drift from the tree.

### The partial clauses — objective 1's remaining work

Each is a clause a test already exercises that does **not** establish it as
written. ⛔ **No total is written here — count the table below**, which is the
only place the number lives. It read "29 clauses" until 2026-08-27, by which
time five had closed and the sentence had outlived two of its own corrections. The fix is normally an assertion plus a
`reason:` on the test named, then a `clauses:` pin — not a new test.

⛔ **Except that for eight of them it is not, because the clause is FALSE.**
All 29 were read against the tree on 2026-08-27, each verdict allowed to be
*"the code contradicts this"* rather than only *"no test asserts this"*. That
returned **12 specification defects** against 17 gaps; an adversarial pass over
every one of the 12 upheld 11 and refuted one (**UC-A4.1 c3**, which is an
ordinary gap).

✅ **All 11 are discharged** (2026-08-27) — four by fixing the code, seven by
correcting the clause — so every remaining partial is now an ordinary gap and
the table below is empty. ⛔ **No count is written out here**; the table is the
count, because it moved four times in a day.

⛔ **The lesson outlives the list, and it is the reusable part.** Write a test
for a clause the tree contradicts and it fails confusingly; the tempting repair
is to weaken the assertion until it passes, which enshrines the wrong behaviour
as the specification. **Open the production path a clause describes before
writing its test.** And keep three verdicts available, not two — "no test
asserts this", "the code contradicts this", and the one that catches the rest:
**"the assertion is true and the REASON beside it is false"**, which is the
hardest to see because the behaviour it describes is correct. Two of the eleven
were that shape, and one more (UC-A4.6 c5) was a claim about *history*, which no
test of the current tree can settle in either direction.

| Clause | What the tree does instead |
|---|---|

✅ **UC-A4.4 c2 was fixed in the code, 2026-08-27.** It said a notification's
scheme decision is the sending app's "exactly as a put's", and it was not: the
legacy fallback lived in `_putInternal` and nowhere else, so one preference
produced a legacy `put` and an `undelivered` notification for the same
recipient — with an exception telling the app to opt into the path it had
already opted into. **Ruled by gkc: extend the fallback to notify.** Both entry
points now catch, the predicate moved to `CryptoRuntime.mayFallBackToLegacy`
because it governs every write path rather than the one it was built for, and
the clause is pinned live on both arms.

✅ **Four were corrected in `acceptance.md` on 2026-08-27 and are now ordinary
gaps**, each with a dated ⚠️ in place saying what it used to claim. Two were the
signing-root privilege gate stated from both sides — **UC-A2.3 c1** ("`alice3`
gets `pq_signing_root`") and **UC-B1.3 c1** ("requests root") — where a scoped
enrollment is neither pushed the private nor permitted to ask, on a rule the
production code states as a security property. Two were the retrofit cap —
**UC-B1.1 c3** and **UC-B2.2 c1** — whose formula the clauses had right and whose
**re-arming** they missed; the correction was that the window has no fixed end,
since each sibling that retrofits extends it by a full grace period. ⚠️ **Both
clauses were rewritten AGAIN on 2026-08-27**, once gkc ruled the guarantee is
per-device and the cap is armed by the child's first authentication rather than by
the retrofit
([decisions.md 118](decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27)).
They now state ruled behaviour the atServer does not yet have, and cannot be
proven until it does.

✅ **Three were fixed in the code instead, on 2026-08-27, and are now ordinary
gaps** — UC-A3.3 c1, UC-B4.1 c1 and UC-B4.4 c1 shared one cause, a negative
cache that left a sender blind to a recipient for fifteen minutes after they
became reachable. The defect, the ruling and the mutation proofs are in
[the plan](../implementation-plan.md#how-the-negative-cache-falsified-three-clauses).
✅ **Two of the three are now closed** (2026-08-27), both by tests that make the
transition happen rather than observing a steady state — the sender is refused
*first*, so what follows is about a client that has already asked and been told
no. **UC-A3.3 c1** is `nskey_data_path_live_test.dart`'s *a namespace that gains
a key takes over*; **UC-B4.4 c1** is `pq_cold_start_recovery_test.dart`, cited
twice because the clause's parenthetical (the opted-in fallback) is a second
test. ✅ **UC-B4.1 c1 closed too, once the clause stopped asking for something `put`
does not do.** It had one arm left — "a PQ self-copy for alice's own scope
proceeds **independently** either way" — which turned out to describe
**AtCollection**, whose self-copy is its own earlier `put` to a plain self key.
`AtClient.put` writes one value and one *recipient-scoped* conveyance, and
`nskey_cross_atsign_test` already asserted the sender cannot open that
conveyance. **Ruled 2026-08-27 (gkc): AtCollection is a consumer and these rows
do not assert its behaviour** — a row about `put` or `notify` is about self→self
**or** self→other, never both — so the reference came out of UC-A4.1's steps,
UC-A4.1's Then, UC-A4.3 c1, UC-B4.1 c1 and UC-B4.3 c1. UC-A4.3 c1 stopped being
a specification defect in the same edit and became an ordinary gap; it was
**closed on 2026-08-29** by varying the sending side, and its row is gone from
the table below.

⚠️ **These are the mapping agents' judgements**, spot-checked at 7 of 91 with
one over-call found. Verify a row against the test before acting on it; the
untested arm is a claim, not a measurement.

⛔ **The clause wordings quoted below are as they stood on 2026-08-27, and the
array-shape sweep has since moved some of them.** The use cases it corrected
that have rows here are **UC-A1.1, UC-A2.1, UC-A3.1, UC-A3.2, UC-A4.1, UC-A4.5
and UC-B1.1** — re-derive with
`grep -oP 'UC-[A-G]\d+\.\d+' on this section rather than trusting the list.
Most of the sweep's edits landed in **Steps** blocks, which no clause is drawn
from, so a row's wording may be untouched; do not assume either way. Re-read the
clause in `acceptance.md` before writing its test — a test written to the
quotation here would be written to a superseded specification, which is the
exact failure the sweep exists to prevent. The rows are still the right work.

⛔ **Both rows examined and deliberately left on 2026-08-27 are now closed.**
`UC-B3.1` c1 wanted a capability-stage notification and got one in
`crypto_era_default_test.dart`; `UC-G1.9` c1 wanted an envelope composed after
a retirement rather than the held key set, and got one in
`signing_key_minting_test.dart`. Neither cost what the note estimated.

**Deferred, not rejected:** UC-A2.4's log names the algorithm adopted from the
keyfile and never names the DIVERGENCE from a configured preference, so a
deployment that set `ml-kem-1024` and got X-Wing must notice for itself. An
explicit warning naming both was proposed and left for when the logging surface
is looked at as a whole.

**Closed so far, and what each cost.** `UC-A1.1` c3 — "nothing encapsulates to
the root, at onboarding or ever" — closed 2026-08-27 by
`pq_signing_root_test.dart`'s `nothing can encapsulate to the root — its
algorithm has no KEM`. It is worth reading before closing another ABSENCE
clause: the wire pin next to it already asserted the record *says* `use: sign`,
and that is a claim about the writer, which a sender is free to ignore. The arm
that was missing is the reader-side one — no KEM behind the algorithm, the
algorithm not offered for key establishment, and the sealing selector returning
nothing when asked for the root's *own* algorithm, which is what isolates
`use: enc` as the reason rather than letting two conditions cover for each
other.

**The standard a closed clause meets**, set by the eight closed on 2026-08-27:
write the missing arm *with a control*, then **mutate the production code and
confirm the failure quotes your own assertion's reason**, revert, and pin. A
green test that has not been shown to discriminate proves nothing.

✅ **Seven more closed on 2026-08-28**, and the shape of the work was the same
each time: read the cited test, find the one arm it exercises but does not
assert, and assert it.

- **UC-C1.5** c1 needed nothing at all — the clause had been rewritten since the
  row was written, and the two live arms already cited (an argless retrofit
  under `pqActive` resolving `mldsa65`, and the same call under `legacy`
  resolving `rsa2048`) establish it as it now stands. The row went on naming an
  idempotence-pool arm the clause no longer has, which is what
  [the wording warning above](#the-partial-clauses--objective-1s-remaining-work)
  says to expect.
- **UC-A2.2** c1 and c3 are two new arms in `copied_keyfile_test.dart`: the
  copy's KEM private half compared byte-for-byte (an id that survived the round
  trip while the seed did not would leave the second host advertising a key
  package it can open nothing with), and a revoke-then-reauthenticate pair on
  one connection shape, whose control is the same copy authenticating a moment
  earlier.
- **UC-A3.2** c1 is a stored self record read by a **second enrollment** of the
  same atSign, added to `nskey_self_notify_live_test.dart` where that pair
  already exists. ⚠️ **Nothing in the tree paired those two before**: every
  multi-enrollment read was cross-atSign, and the self direction was only ever a
  notification. The record's `providerId` is asserted first, without which the
  read passes for a legacy self write — which every enrollment opens, because
  the self encryption key is atSign-wide rather than per-enrollment.
- **UC-B2.1** c1 is a fresh OTP enrollment authenticating moments after the
  capped one was refused, in `retrofit_retirement_e2e_test.dart`. That is what
  *"must re-enroll"* means, and it distinguishes a capped credential from a
  broken atSign.
- **UC-G1.15** c1 is one assertion in `pq_posture_grid_test.dart`: the
  algorithms read back off the atServer equal the ones the sender emitted. It
  was printed and not asserted, and verification cannot stand in for it —
  `verifyEnvelope` passes on the *strongest shared* signature, so an envelope
  that lost one on the way through would verify exactly as well as one that did
  not, leaving all nine cells green.
- **UC-G1.12** c2 is a new test in at_auth, `nothing this API can compose names
  namespaces or an approval state`. ⚠️ **The live test's client half was green
  for the wrong reason** and is now deleted: it built an `EnrollVerbBuilder`
  that named no namespaces and observed that its command carried none. That
  builder *does* carry a `namespaces` field — `enroll:request` needs one — so
  the assertion said only that the test had not set it, and would have stayed
  green for a production composer that filled it in. The replacement drives
  `AtEnrollmentImpl().update` with every field `EnrollmentUpdateRequest` has
  and pins the emitted keys as a **closed set**, because `namespaces` has a
  spelling to look for and an approval state does not: a check for `status` or
  `approval` is a tautology no change to that package could redden.
  Mutation-proven — making the composer emit a namespaces entry reddens it,
  quoting the set.

#### In-process — none left

⛔ **The in-process ones were all closed on 2026-08-27.** Every remaining partial needs a
virtualenv run, and is therefore also the only route that raises
**server-proven**.


#### Live — each needing a virtualenv run to verify

⚠️ **Some of these rows are the specification defects listed above, not test
gaps** — read that verdict table first. This one is left whole because a row
still names the test a corrected clause would be proven by.

⚠️ **The Test column names where the clause is CITED, not where it must be
proven**, and a row sitting here does not make a virtualenv run necessary.
UC-G1.12 c2 was in this table against a live test and closed on 2026-08-28 by a
**unit** test in at_auth, because the arm it was missing is about what the
client composes — which a live atServer cannot witness any better than a
capturing mock can, and which the live arm had been asserting on a builder it
never populated. Ask what would witness the missing arm before assuming the
answer is the cited pack.

Rows that genuinely need the wire are also the only route that raises
**server-proven**.

| Clause | The arm nothing establishes | Test |
|---|---|---|
| **UC-A4.6** c5 | where they had exchanged `0x01`, with no readers-upgrade-first migration — and that is what later made it safe to drop `0x01` outright | `secret_sharing_delivery_test.dart` |
| **UC-B0.1** c1 | "(The atServer's immutable write is long-standing and present even here — it is **not** a PQ-only verb.)" — nothing exercises an immutable… | `legacy_server_abort_test.dart` |
| **UC-B1.2** c1 | it mints its **own** PQ APKAM keypair | `retrofit_e2e_test.dart` |
| **UC-B2.2** c1 | legacy auth survives until `min(now + grace, expiry)` | `retrofit_retirement_e2e_test.dart` |
| **UC-B4.3** c1 | "which `alice2` cannot read" — nothing establishes that a pre-capability (legacy-only) install FAILS to read a record stamped `at/symmetric/AES/GCM`. ⚠️ **Measured 2026-08-29: the at_talk demo cannot evidence this, and was proposed for it.** Every atSign in that demo runs the same current binary and `--posture legacy` sets one preference field, so its "old install" is a current build configured for legacy crypto — which would pass whether or not a genuinely old one refuses. Its own event counts also show no legacy-posture atSign is ever handed a non-legacy `providerId`, because a pqActive sender refuses at the SENDER toward a recipient that has published no namespace key: evidence about a writer declining, not about a reader failing. The realistic peer is a PUBLISHED version — `at_client` **3.14.0** has the provider concept and none of the PQ provider ids, and its `crypto_runtime.dart` `_provider` throws `CryptoProviderNotRegistered` for an unknown non-legacy id, the registry there being the `CryptoConfig` itself. ✅ **Measured 2026-08-29** in a throwaway package resolving `at_client` 3.14.0 from pub.dev (`source: hosted`), handed a key whose `appMetadata.providerId` is `at/symmetric/AES/GCM`: it throws `CryptoProviderNotRegistered` — *Registered providers: legacy* — with no preferences passed, so the refusal is what an UNCONFIGURED 3.14.0 does rather than a configured one. It is `CryptoRuntime._provider`'s throw and not `legacy_decryption`'s `StateError`, which that route never reaches; a `legacy` id and an absent `appMetadata` both get past `_provider` in the same probe, which is the control that says the result is about the provider id. ⛔ **The clause is still owed**, because that probe reaches `CryptoRuntime` through an implementation import and drives a fake client. A shipped arm needs the public surface a consumer would use, in a package that resolves at_client from pub.dev — this workspace pins it by path — so it is its own job rather than a test edit | `nskey_cross_atsign_test.dart` |
| **UC-B5.1** c1 | "`pq_signing_root` is root (no namespace), so it has **no** `enroll:listns` push" — and, within the second arm, "(persists until one answer… | `signing_root_pull_two_enrollments_test.dart` |
| **UC-G1.10** c1 | `_apsk` is **not** rewritten: … so the client sends none and the atServer leaves the record's own value alone | `enroll_update_live_test.dart` |

#### Section 17 — the crypto-agility clauses, and what each waits on

⛔ **These were never in the mapping above.** Section 17 was written on
2026-08-27 from
[decisions.md 119](decisions.md#119-crypto-agility-each-advertisement-adds-and-the-signer-chooses-2026-08-27),
120 and 121, long after the 2026-08-23 walk that produced the table above, so
"nothing MAPPED is untested" says nothing about them. **Count them by running
the suite**, not from a figure here — they are the bulk of what is unproven.

**Most of them are not test gaps.** They describe mechanisms the tree does not
have, so no assertion can close them until something is built, and each waits on
a `## TODO` row in [the plan](../implementation-plan.md#todo). What follows is
the mapping from clause to row. **Measured 2026-08-28**, by reading the
production paths named:

- ~~**The nskey mint is singular.**~~ ✅ **Both landed 2026-08-28.** The mint
  now writes a key for every configured algorithm and files each private under
  its own kid; `PublishedNskeyKeyRing.add` puts one client's newly minted
  material into the **current** generation in place, under the same mint lock,
  preserving every existing kid and the generation's `createdAt`. **UC-G2.6**
  c1, c2, c3 and c5 are pinned, and **UC-G2.5** c1 stopped being degenerate —
  "whatever algorithms that generation named" is now asserted over two.
  ⛔ **What is left of that row**: c4 (only the newly minted private is
  conveyed) and c6 (the added document is re-signed by the *adding* enrollment)
  want the same fixture — a generation minted by one enrollment and added to by
  another — which is a live shape rather than a unit one. **UC-G2.11** c1 and
  c2 are the same live shape seen from the reader's side.
- **A rotation excludes the enrollment named and nothing else.**
  `revokeEnrollmentAndRotate` passes `excludeEnrollmentIds: {enrollmentId}`.
  ⛔ **SPENT.** That was **UC-G2.5** c4, the subtree exclusion — WITHDRAWN
  2026-08-31, because ruling 129 puts the walk in the atServer's revoke and the
  one-element exclusion set the client passes is correct as it stands.
- **Nothing anywhere carries a revocation timestamp**, which is why
  [decisions.md 121](decisions.md#121-a-revocation-publishes-what-it-obliges-2026-08-28)
  ruled that the revoker writes a durable record. ⛔ **SPENT — ruling 130
  reverses that**: the atServer stamps `revokedAt` on the enrollment and no
  client publishes anything. The clause is now **c5** (the withdrawal of the old
  c4 renumbered everything after it), whose own
  ⚠️ says the advertisement cannot answer the revocation half.
- **A signature names its signing enrollment, not its key.** The protected
  header is `{alg, typ, kid, v}` and `kid` is the enrollment id
  (`envelope_signature.dart`). So **UC-G2.8** c2 and c3, and **UC-G2.7** c3
  where it turns on the same field.
- **A verifier has no accept lever for signatures.** `AtClientPreference` has
  four algorithm levers — `dataSigningKeyAlgorithms`,
  `authenticationKeyAlgorithm`, `sealsToKeyAlgorithms` and
  `keyEstablishmentAlgorithms` — and only the last is an accept side, on the
  encryption half. So **UC-G2.9** c4, and c1 and c2 which state the consequence.

⛔ **One question the triage did not settle, left for gkc.** **UC-G2.9** c1
and c2 are absence claims that are TRUE of the tree today — there is no
minimum-algorithm check, no signature-count check and no accepted-algorithms
field for signatures in `AtClientPreference`. They could be pinned now by a
guard that reddens exactly when step 3's accept lever lands, which is either a
useful tripwire or a clause counted proven for describing a hole. The list
above files them as waiting on the lever, and that is unchanged until ruled on.

⛔ **Two clauses now wait on the same piece of TOOLING, not on a test.**
**UC-B4.3** c1 and **UC-G2.10** c6 both need a client that genuinely lacks a
capability rather than a preference that declines to use one, which means a
package resolving a PUBLISHED `at_client` from pub.dev — this workspace pins it
by path. One package would serve both, and until it exists neither clause is a
test gap in the ordinary sense.

**The eight the list above does not reach, triaged 2026-08-29** — six test gaps, one needing a differently-built client, and one withdrawn. Triaged by reading the
production path each one names. The verdict column is the one that matters: a
clause the tree CONTRADICTS and a clause nothing tests look identical to every
instrument here, and only the second is a test gap.

| Clause | Verdict | What was read |
|---|---|---|
| **UC-G2.5** c2 | **test gap, and newly reachable** | the clause's content is that a rotation does not mint an algorithm the configured set has dropped. `nskey_rotation_test.dart`'s *a rotation mints the whole configured set afresh* already proves material is not carried forward, over two algorithms — but it holds the set CONSTANT (`second.keys.map(alg)` equals `first`'s), so nothing exercises a narrowing. The missing arm rotates with a narrowed set and asserts the dropped algorithm is absent |
| **UC-G2.5** c7 → now **c6** ✅ **CLOSED 2026-08-31** | ~~test gap — the mechanism exists~~ | `mint_lock.dart` carries the loser path in production: *"the caller takes its ordinary loser path: it re-reads what … the re-read is what every caller already does"*, and it logs `is already held; re-reading rather than …`. The refusal is pinned (*a rotation inside the mint lock's cooldown is refused*, *a client that loses the mint lock adds nothing*); the back-off-and-re-decide half is not |
| **UC-G2.7** c4 | ✅ **CLOSED 2026-08-29**, and its justification was false | the assertion holds and is now pinned by two citations — the existing `published_nskey_key_ring_test` reader arm, which was unpinned, and a new `nskey_rotation_test` arm proving the generational half: after a rotation every entry of the successor is still offered for new work, and what opens history is the previous generation's private, still filed. Mutation-proven against production — dropping `offeredForNewOperations` from `bestKeyFor` reddens the reader arm. ⛔ **The clause named THREE writers of a retired entry and there are two.** `PqSigningRoot._publish` is the root record's only writer, emits a single-entry `keys` list with no `status`, and production says beside it that *no rotation exists to repair it with* — so nothing can add a second entry. Corrected in the catalogue in the same commit |
| **UC-G2.7** c5 | ⛔ **not an assertion — WITHDRAWN 2026-08-29** (gkc) | it scoped the row against UC-G2.3 rather than asserting a behaviour of its own. After a retirement and after a compromise the key material is in the same state — the entry stays advertised either way — so the two differ only in the status token, and `KeyEntryStatus` has one: `active` and `retired`, with `revoked` named in its dartdoc as a hypothetical. Pinning it against an unknown token would have proven UC-G2.3's clause under this row's name, which is the conflation the sentence forbids. It is now prose beneath the row and out of the denominator |
| **UC-G2.10** c3 | **test gap** | *the recipient does nothing further* is an absence over @bob's behaviour after publishing a widened advertisement — no re-seal, no re-conveyance, no learning whether @alice upgraded. Testable by counting what @bob writes after the publish; nothing counts it today |
| **UC-G2.10** c5 | **test gap, two-sided** | both failure modes are behaviours: across atSigns the sender reads the recipient's advertisement and refuses **before any record exists**; within one atSign the writer seals to its own advertisement, nothing refuses, and a sibling install meets it later. The second half is UC-G2.11 c3's shape |
| **UC-G2.10** c6 | ⛔ **needs a differently-BUILT client** | omitting an algorithm is `sealsToKeyAlgorithms` policy and is exercised; not implementing one is the build, and every arm covering this row varies a preference over algorithms both builds hold. Same shape as **UC-B4.3** c1 above, and the same answer: a package resolving a published at_client, not a preference |
| **UC-G2.11** c3 | **test gap** | an `alice1` that mints only the new algorithm writes records `alice2` cannot open, and the refusal is the ladder working. `nskey_rollout_ladder_live_test.dart` already runs two enrollments of one atSign at different algorithm configurations, which is the fixture this needs |

⚠️ **`liveProofOwed['UC-G2.5']` was stale when this was written**, and is
corrected in the same commit. It said *"today the mint produces one key so
'carries nothing forward' is trivially true of it"* — while the list above
records the plural mint landing on 2026-08-28 and `nskey_rotation_test.dart`
proving it over two algorithms. One fact, two homes, and the one nobody was
editing rotted. The reason a row is owed decays exactly like a count.

**Six were ordinary test gaps and are closed** (2026-08-28). Each is named
below with the test that closed it, because a test no document names is work
the next reader rebuilds:

- **UC-G2.8** c1 — `jws_envelope_test.dart`, *and however the ADVERTISEMENT is
  ordered*. Its sibling varies the envelope's signature order; every arm of
  that group published `_apsk` **RSA-first**, so nothing said the
  advertisement's order does not decide either. Mutation-proven against
  `shared.first`.
- **UC-G2.9** c3 — `jws_envelope_test.dart`, *no shared algorithm names BOTH
  documents, and does not fall back*. UC-G2.9's own case rather than a
  relabelling: an ML-DSA envelope against an RSA-only advertisement.
- **UC-G2.5** c3 — `nskey_rotation_test.dart`, two arms: *publishes a fresh
  generation and keeps the superseded private* now compares the advertised
  **keys** rather than the kids (a kid is derived from its key, so the kid
  assertion was about the derivation), and *does not push to an excluded
  enrollment* shows the exclusion reaching the roster query.
- **UC-G2.5** c5 → now **c4** — `ck_manager_test.dart`, *cuts a fresh CK when the
  destination has rotated its nskey*, which already existed and was unpinned.
- **UC-G2.10** c4 — `nskey_resolver_test.dart`, *a narrowed list refuses, and
  the message names both sides*, which also already existed.
- **UC-G2.10** c1 — closed too, but only after fixing the code; see below.

⛔ **UC-G2.10 c1 was not a test gap — the tree contradicted it, and this list
said otherwise until 2026-08-28.** A sender could not reach the second entry of
a widened nskey advertisement at all. **Fixed the same day**, and the account is
kept because the shape recurs. Measured first with a throwaway probe over an
advertisement carrying an ML-KEM entry and an X-Wing one:

```
advertisement.alg = x-wing        keys = [ml-kem-1024/dfeab4…, x-wing/02f6b4…]
x-wing      : SEALED and OPENED ok
ml-kem-1024 : REFUSED -> @alice:myapp advertises a x-wing nskey,
                         which at/nskey/MLKEM1024/AES/GCM cannot seal to
```

**The two layers disagree about which entry is in play.** `NskeyResolver` was
widened and selects per entry, honouring the sender's `sealsToKeyAlgorithms` —
which `nskey_resolver_test.dart`'s *a widened advertisement serves each sender
the entry IT understands* now pins, as a differential over one advertisement so
that neither narrowing could be satisfied by a constant. `CkManager` then routes
to the provider for that entry's algorithm — and `NskeyProvider` re-derives the
algorithm from `NskeyAdvertisement.alg`, the **single-key compat getter**
(`_usable`, the best key over everything the *build* supports), and refuses on
the mismatch. `advertised.publicKey` and `advertised.nskeyKid` beside it are the
same getter, so even a passing seal would address the wrong entry.

That guard is right for a single-key advertisement — `a provider will not seal
to the other KEM's advertisement` pins it, and encapsulating under the wrong KEM
produces a record the owner can never open. It is wrong for a multi-key one: it
has to compare against the **entry being sealed to**, not against the document.
`NskeyPrivateFiling` (`advertised?.alg`, `advertised.publicKey`) and
`ConveyedKeyCollection` (`advertised.nskeyKid`) read the same getters.

It was **latent, not live**: the mint was singular, so no atSign published a
widened advertisement. It would have become reachable the day one did — and it
did, hours later on the same day, when the plural mint landed. That ordering is
the whole of *the reader ships first*, and it was luck rather than method that
the two happened in the right order: the reader defect was found by writing a
test for a clause the worklist had called a test gap.

**The fix.** `NskeyAdvertisement` gained `entryWithKid(kid)`, the counterpart of
`usableFor(algos)` for a party holding a kid rather than an algorithm.
`NskeyProvider.encrypt` now selects `usableFor([keyAlgo])` — the entry it was
routed to — and seals to *that* key and stamps *that* kid; its refusal names
every algorithm on offer rather than the one the document's getter picked.
`NskeyPrivateFiling` selects by kid for both the algorithm it expands the seed
under and the public half it compares against; `ConveyedKeyCollection` asks
whether **any** entry carries the kid rather than comparing `nskeyKid`.

⚠️ **The filer's fix broke a real refusal on its first attempt, and the suite
caught it.** Reading "no entry under this kid" as *no opinion* let through the
case that arm exists for — a private that is genuinely this atSign's and
genuinely an nskey private, for a generation peers are not sealing to. It falls
back to the document's own single-key answer when no entry matches, which is the
old behaviour exactly; the widened case never reaches the fallback, because
there the entry is found.

**What proves it**, both mutation-checked separately:
`nskey_kem_selection_test.dart`'s *either entry seals and opens, and each stamps
its OWN kid* (reverting the provider reddens it with the probe's own refusal),
and `nskey_resolver_test.dart`'s *a widened advertisement serves each sender the
entry IT understands* (making `usableFor` ignore its argument reddens it). The
stamped kid is asserted **before** the round trip: a wrong kid fetches the wrong
private, so otherwise it reddens as a decapsulation error and proves nothing
about the stamp.

**Still owed on this row:** **UC-G2.10** c3, "the recipient does nothing
further". It is an absence — no re-seal, no conveyance fired — and a test that
merely succeeds at reading is satisfied either way, so it needs its own arm.

⚠️ **UC-G2.7** c4 and c5, **UC-G2.9** c2, **UC-G2.10** c5 and c6 and
**UC-G2.11** c3 have **not** been read against the tree. They are commentary
clauses — they contrast two mechanisms, or name which of two failures is the
better one — and whether a test can express any of them is an open question
rather than a known gap. Read them before writing anything.

### The proven clauses still owed a citation

✅ **All 33 are written, and this list is empty.** It read "**33 clauses** …
needing **33 new `provenIn` calls**" when the table below was generated, and the
table is left as it was so the work is legible.

⚠️ **The last one — UC-A2.4 c3 — was withheld for a day rather than forgotten**,
and what it was waiting for is worth keeping. The live test asserted the `pqSeal`
version byte against `sealVersionFor()`, the function that puts the byte there,
so the two sides moved together and the assertion pinned nothing. It was pinned
on 2026-08-27 by replacing that with the raw literal `0x03` (and `0x02` on the
X-Wing arm), and the discrimination was **measured rather than argued**: under a
mutation that renumbers the wire consistently — swapping the cases in both
`algo_ids.dart`'s `sealVersionFor` and at_chops' `_versions` table, so sealing
still works end to end — the old assertions pass with **exit 0** while the
literals redden quoting their own reason. ⛔ **The obvious one-sided mutation
does not prove this**: swapping only `sealVersionFor` makes `pqSeal` itself throw
`version 0x3 is KEM 0x42 … this KEM produced 1120` during enrollment, so the
suite goes red for a reason that has nothing to do with the assertion.

Three of the citations below named a test proving a *different arm* of the
clause than the pin claims; each was written against the right test instead.

⛔ **Do not generate these mechanically.** It was tried and reverted. A
mapper's evidence for one clause spans several files, so collapsing it into a
single citation's `proves:` produced a sentence naming a *different* test from
the one cited, and pulled a planning reference into a code comment. `proves:`
is the sentence a reviewer judges the citation by; each gets written after
reading the test.

| Row | Clauses | Test to cite |
|---|---|---|
| **UC-A1.1** | c5 | `nskey_data_path_live_test.dart` — a write to a namespace with no nskey fails, saying which |
| **UC-A1.1** | c6 | `pq_legacy_interop_live_test.dart` — UC-B4.2 opt-out · an atSign that refused legacy material is no |
| **UC-A1.1** | c2 | `pq_signing_root_mint_lock_test.dart` — a second signing-root mint lock create is refused |
| **UC-A2.1** | c3 | `pq_signing_chain_test.dart` — climbs a chain link to an anchored parent *(in-process)* |
| **UC-A2.1** | c2 | `enrollment_chain_link_live_test.dart` — the root private reaches a privileged enrollment and no other |
| **UC-A2.1** | c5 | `nskey_rotation_live_test.dart` — UC-A5.2/A5.3 · a revoked enrollment cannot authenticate |
| **UC-A2.4** | c3 | `key_package_amendment_live_test.dart` — UC-A2.5 · a sender picks by its own order and stamps the match |
| **UC-A3.1** | c2 | `nskey_data_path_test.dart` — a client lacking the nskey private cannot decapsulate the CK *(in-process)* |
| **UC-A3.1** | c1 | `nskey_data_path_test.dart` — alice1 writes, alice2 syncs both records and round-trips plain *(in-process)* |
| **UC-A3.2** | c3 | `enrollment_namespace_gate_test.dart` — a scoped enrollment cannot read the envelope channel of a name |
| **UC-A3.2** | c6 | `nskey_data_path_live_test.dart` — a write to a namespace with no nskey fails, saying which |
| **UC-A3.2** | c4 | `nskey_self_heal_live_test.dart` — an enrollment that missed the mint pulls the private from a ho |
| **UC-A3.2** | c2 | `underscore_public_key_hiding_test.dart` — a public:__ key syncs, is served by plookup, and is not enumer |
| **UC-A3.3** | c3 | `cold_start_test.dart` — a self write to an unminted namespace refuses the same way *(in-process)* |
| **UC-A3.3** | c2 | `nskey_seeding_test.dart` — an enrolled client seeds the namespaces its enrollment grants *(in-process)* |
| **UC-A3.4** | c4 | `a3_self_data_test.dart` — UC-A3.4 · self notification carrying an encrypted value *(in-process)* |
| **UC-A3.5** | c5 | `nskey_kem_selection_test.dart` — and refuses an owner that only opens the retired construction *(in-process)* |
| **UC-A3.5** | c1 | `nskey_minting_test.dart` — the published advertisement emits its exact wire shape — raw l *(in-process)* |
| **UC-A4.1** | c2 | `cross_cutting_test.dart` — no RSA in any confidentiality path for a fully-PQ interaction *(in-process)* |
| **UC-A4.2** | c3 | `nskey_cross_atsign_test.dart` — isReadyFor goes from false to true when bob mints |
| **UC-A4.2** | c2 | `pq_legacy_interop_live_test.dart` — UC-B4.2 outbound · a PQ app on @bob reaches a legacy @alice th |
| **UC-A4.4** | c4 | `a3_self_data_test.dart` — UC-A3.4 · self notification carrying an encrypted value *(in-process)* |
| **UC-A4.5** | c4 | `nskey_minting_test.dart` — the published advertisement emits its exact wire shape — raw l *(in-process)* |
| **UC-A4.6** | c2 | `pq_hpke_test.dart` — a KEM that is not the version *(in-process)* |
| **UC-A4.6** | c4 | `key_package_registration_test.dart` — a declared suites list is what the sender negotiates against *(in-process)* |
| **UC-A4.6** | c1 | `pairwise_secret_sharing_test.dart` — refuses a peer that only opens the retired construction *(in-process)* |
| **UC-A4.6** | c3 | `key_package_amendment_live_test.dart` — UC-A2.5 · a sender picks by its own order and stamps the match |
| **UC-A4.7** | c2 | `pairwise_secret_sharing_test.dart` — pushSecretToNamespaceMembers skips it and still reaches the re *(in-process)* |
| **UC-B1.1** | c4 | `pq_advance_ladder_test.dart` — one enrollment walks legacy to pqReady to pqActive, and nothin |
| **UC-B1.5** | c1 | `pq_advance_ladder_test.dart` — one enrollment walks legacy to pqReady to pqActive, and nothin |
| **UC-B3.2** | c1 | `nskey_data_path_live_test.dart` — a self value round-trips through the nskey data path |
| **UC-B5.2** | c1 | `b5_edge_cases_test.dart` — UC-B5.2 · reading legacy history after retrofit *(in-process)* |
| **UC-B5.3** | c1 | `pq_signing_root_test.dart` — losing the mint lock generates nothing and files nothing *(in-process)* |

### Clauses pinned in the tree that the map calls partial

Pins that predate this mapping, where a clause carries an arm the cited test
does not reach. Each is a candidate over-claim: the burn-down counts them, so if
they do not survive review the recorded figure falls.

⚠️ **Nine rows are pinned-and-partial and only the one in the table below means
anything.** Eight — UC-G1.2 c1, UC-G1.3 c1, UC-A3.5 c3, UC-A3.5 c4, UC-C1.6 c1,
UC-A2.5 c5, UC-A2.4 c5 and UC-G1.1 c2 — were closed or corrected on 2026-08-27,
so the map's PARTIAL verdict for them is a stale snapshot rather than an
over-claim. A count taken from the map alone would say nine.

⛔ **The heading above carried the count until 2026-08-27** ("Two clauses pinned
…"), which put the number in a third home *and* in a linked anchor, so
correcting it meant editing a pointer in another file. It does not carry one now.

| Clause | The arm the cited test does not reach |
|---|---|
| **UC-A2.6** c2 | an enrollment revoked while it holds an already open, already authenticated connection |

✅ **UC-G1.1 c2 was the second row here and is closed** (2026-08-27). It was
reached independently: reading that test by hand found the same defect before
the map was consulted, and the hand read found it worse than the map did. The
cited test's fixture is legacy-only, so the resolver answers **null** — which
makes "authentication read the flat field" and "the resolver had nothing to
offer" the same observation — and neither of its two assertions calls
`authenticate` at all; both are about the document. What closed it is a second
test on a **retrofitted** keyfile, the one shape where both sources answer and
they differ (flat `legacy-1`, resolver `new-123`), asserting on the id that
reached `PkamAuthenticator`. Mutation-proven with its control kept **separate**:
making `authenticate` consult the resolver reddens the assertion quoting its own
reason and leaves the explicit-id test green (`+1 -1`). ⚠️ **As two assertions
in one body the control could not have shown that** — the second never runs once
the first fails, so a control after the assertion it guards is untested by
construction.
