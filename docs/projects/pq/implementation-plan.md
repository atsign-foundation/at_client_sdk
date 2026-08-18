# implementation-plan.md — TODO / PARKED / DONE

Three sections, one per state. **TODO carries full detail**, because it is what
the next session works from. **PARKED and DONE are one row each**, with the
detail in [`detail/implementation-plan.md`](detail/implementation-plan.md).

**Item ids are permanent.** `14.13` and `14.19 item 11` are cited from
production dartdoc and from `blockers.dart`, so an item keeps its id when it
moves between these three sections. Nothing here is ever renumbered.

**To add an item:** put it in TODO with its detail. When it lands, replace it
with a DONE row and move the detail to the detail file. When it is set aside,
give it a PARKED row whose reason is enough to stop someone building it — that
is the row's whole job.

When an item finishes, move its detail to `detail/implementation-plan.md` and
leave the row here. That is a judgement about *state*, not about length — this
file carried a line ceiling until 2026-08-17, and it made size the trigger for
a demotion that should follow completion.

⚠️ **Re-derive before acting on any row below.** Every "current state" table in
this project has been wrong at least once by being carried forward; the
commands that re-derive these are in
[Re-deriving the state](#re-deriving-the-state) at the end.

**D1 initial development ends at step 34** — the spike carved into stacked PRs
and merged. Publishing and R-2 follow it and are not D1.

---

## TODO

| Item                            | What is owed                                                        | Blocked on                                                                       |
|---------------------------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------|
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | Steps 32–34: carve into stacked PRs, merge to trunk | The published atServer image verifying ML-DSA PKAM. Touches step 32 only |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | Step 20's rotation arm — enrollment then an `enroll:update` APKAM rotation mid-run | An at_auth release carrying the tolerant reader, then the staged status value. Needs its own CRAM atSign |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | **10** open small items — the items are in `detail/`, none of them blocking. Re-derive rather than quoting: this row said 17 while the count was 10, and the comment beside the command said 17 for two days after the row was fixed | Item 8 is the only one waiting on a ruling. Items 20 and 21 are examined-and-left, not work |
| [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | Three audit residuals — UC-A3.4's live self-direction was the fourth and is done | — |
| [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) | A client with no enrollment id is treated as fully privileged | Wants a ruling on whether an owner-keys client belongs in the enrollment trust model |
| [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | A `mintLegacyMaterial:false` atSign cannot write a public record | Two moves its body names, neither scheduled: public-record signing onto the ML-DSA signing root, and self data off `selfEncryptionKey` onto the nskey path (B-3 phase 1). ⚠️ This cell read "Gates the stop-release" until 2026-08-18 — which is what 14.12 *blocks*, so anyone scanning this column for what is ready to start misread the row as ready |
| [14.11](#1411-deprecated_member_use-findings-across-the-workspace) | `deprecated_member_use` across the workspace | A call-site migration, not a lint sweep |
| [14.7](detail/implementation-plan.md#147-noports-carries-its-own-copy-of-the-envelope-shape) | NoPorts carries its own copy of the envelope shape | Separately owned — named here, not fixed here |
| [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart) | `self_enrollment_retrofit_live_test.dart` failed once in five pack runs | Unexplained. Not a flake and not fixed — a rate, not a kind |
| [14.29](#1429-the-residuals-1425-surfaced) | SS-2's `__ssenv` and two small S-3 items — none blocking. Re-read 2026-08-18: B-1's residuals had shipped and S-3's migration test existed, so this row said **three B-1 residuals, three small S-3 items** against an actual none and two | — |
| [14.37](#1437-retire-the-0x01-seal-version) | Retire `pqSeal` version `0x01` — two commits, in order | Nothing. [Ruling 110](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18) settled it; only the order is constrained |
| [14.38](#1438-activate_cli-cannot-administer-a-pq-native-atsign) | `activate_cli` cannot administer a PQ-native atSign — 2 code fixes and a test repair | Nothing. Cause pinned and the shape agreed; [#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161) carries the evidence |
| [14.39](#1439-pqposture-and-the-rollout-it-drives) | `PqPosture` — the rename, the 3 postures, client-driven retrofit, the algorithm lists, and public-data signature verification | Nothing. Design settled by [ruling 113](detail/decisions.md#113-pqposture-replaces-releaseposture-and-drives-the-rollout-2026-08-18); large, and it changes R-2's definition |

### 14.39 `PqPosture` and the rollout it drives

Design settled with gkc on 2026-08-18 and recorded as
[ruling 113](detail/decisions.md#113-pqposture-replaces-releaseposture-and-drives-the-rollout-2026-08-18),
which carries the posture matrix, the 8 rulings and the reasoning. This row is
the work, which is large and touches at_client, at_auth and at_onboarding_cli.

**The class.** `ReleasePosture` becomes `PqPosture` with 3 pre-built constants
— `legacy` (default), `pqReady`, `pqActive` — and a program may build and
inject its own. `SigningRollout` is deleted, replaced by `authenticationKeyAlgorithm`
and `dataSigningKeyAlgorithms`. `mintLegacyMaterial` becomes an axis pinned true
in all three. Construction rejects `disallowLegacyEncryption` true where
`writesPqByDefault` is false, since such a posture refuses its own writes.

**The behaviour.** A posture is a floor and never downgrades: key material wins
for authenticating and reading. The client drives its own retrofit at start, in
the same shape as the nskey mint — every start, non-blocking, local state
checked first, failure retried next start, usable meanwhile. Nothing is needed
for capping; the atServer's 720-hour grace already re-arms per sibling and
exempts the first enrollment.

**The narrowing.** `disallowLegacyEncryption` becomes posture-only and its
`AtClientPreference` override goes, which overturns ruling 70's
individual-flags-win for that flag and **redefines R-2**
([#2016](https://github.com/atsign-foundation/at_client_sdk/issues/2016)) as
"the default posture becomes `pqActive`". That issue needs rewriting when this
lands.

**The lists.** Posture supplies defaults, `AtClientPreference` holds the values.
Two are needed and neither exists in the right shape: a receiver-side list of
what this atSign publishes for others to seal to, which is today the singular
`keyEstablishmentAlgo` and is the same singularity as
[14.37's sibling](#1437-retire-the-0x01-seal-version) issue
[#2135](https://github.com/atsign-foundation/at_client_sdk/issues/2135); and a
sender-side list of what it will seal to, today `static const` in
`SecretSharingAlgos`. Verification and decryption stay maximal and are never
posture-settable, so *reads are universal* holds by construction.

**The rename.** Every parameter, variable and class says whether it means the
PKAM authentication signing key or the data signing key. Scope is at_client and
at_onboarding_cli. at_chops' `AtSigningInput.signingAlgoType` is deliberately
left alone — 165 hits across 48 files, unambiguous in context, and it would open
an at_chops version ruling 109 avoided. Measured blast radius for the rest:
`ReleasePosture` 112 hits in 23 files, `SigningRollout` 77 in 20, `signingRollout`
77 in 19, `inUseSigningAlgorithms` 95 in 22, `retrofitAuthenticationAlgo` 13 in 6.
⚠️ The acceptance rows `UC-C1.x` and ruling 70 move in the same commit.

**The CLI.** `--posture legacy|pqReady|pqActive` on every command, defaulting to
at_client's built-in. No `--disallowLegacyEncryption` anywhere.
`at_onboarding_cli` majors when it takes at_client 4.x.

**Public-data signatures.** ⚠️ **Nothing verifies `metadata.dataSignature`
today** — not at_client, not the atServer — so this builds the first verifier
rather than extending one. `pqActive` signs with the enrollment's data signing
key in the `_apsk` envelope form, and the verifier walks the signer's `_apsk`
through the approval chain to `pq_signing_root`. `pqReady` changes nothing.
Verification runs automatically on public reads, non-fatally, with the outcome
exposed; it wants the signer's `_apsk` cached or every public read pays a remote
lookup on another atSign. Both forms are read, and the legacy form permanently,
because every public record a released at_client signed sits on a live atSign.

### 14.38 `activate_cli` cannot administer a PQ-native atSign

Found 2026-08-18 driving `activate_cli` against a throwaway virtualenv.
Evidence, reproduction and the rejected alternatives are in
[#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161); this
row is the work.

An atSign activated with `--signingAlgoType mldsa65` cannot then run `otp` or
`list`: both fail with `RangeError`, because the connection signs the PKAM
challenge as RSA-2048 with an ML-DSA key. `otp` is where a second enrollment
starts, so a PQ-native atSign cannot enrol a second app.

at_client resolves the algorithm correctly and `RemoteSecondary` stamps it on
the lookup. `AtOnboardingServiceImpl._initAtClient` then overwrites it from the
preference at `at_onboarding_service_impl.dart:139`. The comment above that
line says activation has no key material to resolve from, which is true for the
`onboard` caller and false for the `authenticate` caller, and the method serves
both.

**Three changes, agreed with gkc 2026-08-18.**

1. **Delete** the overwrite at `at_onboarding_service_impl.dart:139`. It is
   redundant rather than misplaced: `RemoteSecondary` already sets the lookup
   from `signingAlgoOf(client)`, which falls back to the preference when
   nothing was resolved, and `AtOnboardingPreference extends AtClientPreference`
   with the same object reaching the client. Verified, so activation is
   unaffected.
2. **Fix `at_client_impl.dart:1584`**, the file-stream `RemoteSecondary`, which
   passes neither `signingAlgoType` nor `enrollmentId` and signs with the same
   default.
3. **Repair** `tests/at_onboarding_cli_functional_tests/test/pq_native_onboard_test.dart`
   rather than adding a test beside it. It runs the defective line today and
   passes anyway, because it sets `preference.signingAlgoType` to `mldsa65`
   itself, so the overwrite writes the right value back, and because it drives
   its remote command on the activation client rather than the one from the
   fresh `authenticate()`. Leave the preference at its default so key-material
   resolution is the only thing that can make it pass, drive a remote operation
   on the freshly authenticated client, and keep an rsa2048 arm in the same run
   so the two provably differ.

⚠️ **Not doing, deliberately.** `AtLookupImpl.signingAlgoType` still initialises
to `rsa2048` (`at_lookup_impl.dart:739`), so any site that forgets authenticates
with the wrong routine silently. Making it required at construction would let
the compiler enumerate every site, but at_lookup's in-tree 3.6.1 equals its
published 3.6.1, so touching it opens 3.6.2, which
[decisions 109](detail/decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18)
established is not needed. This rides the next at_lookup version whenever one
opens for another reason.

`--signingAlgoType` also stays a silent no-op on non-onboard commands, which
build their preference through `create_at_client_cli.dart` without copying it.
Once the overwrite is gone it has no effect there anyway, and a posture
argument covering legacy / rollout 1 / rollout 2 is under discussion which may
replace the flag.

### 14.37 Retire the `0x01` seal version

[Ruling 110](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18)
(gkc, 2026-08-18) retires `pqSeal` version `0x01` — the `x-wing-hpke-v1` suite,
X-Wing under the bespoke `atPQv1-base` key schedule with AES-256-GCM. `0x02` and
`0x03` are RFC 9180 Base verbatim and checked against the IETF working group's
vectors, so the homegrown schedule earns nothing beside them. The ruling has the
reasoning, including the four arguments for keeping it and why none carries;
this row is the work.

**Two commits, and the order is the whole of it.**

Commit 1 stops anything emitting `0x01`. Drop `xWingHpke` from
`SecretSharingAlgos.suites` in `packages/at_client/lib/src/secret_sharing/algo_ids.dart`,
and leave it in `openableSuitesFor(xWing)` so a holder still advertises that it
can open one. Nothing changes for two current builds, which already negotiate
`0x02` first; what goes is the path that reaches `0x01` at all.

Commit 2 removes the version, once nothing can be sealing under it: the row from
at_chops' `_versions`, the constant from `pqSealSupportedVersions`, the entry
from `SecretSharingAlgos.sealVersionFor`, `xWingHpke` from `openableSuitesFor`
and its declaration, and `pqSealDefaultVersion` moves off `0x01`. Nothing in the
tree reads that default — `pqSealToBase64` makes `version` required and both
call sites pass a negotiated value — so moving it is bookkeeping rather than a
fleet decision, whatever its dartdoc says about raising it.

`docs/projects/pq/seal-spec.md`, `packages/at_chops/test/vectors/pq_seal_v1.json`
and `pq_seal_conformance_test.dart` move with commit 2, not before it. The spec
exists so a second implementation can build `0x01`; retiring the version retires
the reason for the document.

⚠️ **Why the two commits are separate.** Removing a supported version turns any
record already sealed under it into a permanent `PqOpenFailure.versionMismatch`.
Nothing outside this tree holds a `0x01` envelope today and `__ssenv` entries
expire at 7 days regardless, so the window costs nothing — the split is what
makes it safe to have been wrong about that.

**Sweep with it.** `at_chops`' CHANGELOG needs an entry, and `design.md` and
`acceptance.md` both name the three versions; `acceptance.md` cites `seal-spec.md`
for "the three versions and what each is attested by", which becomes two.

### 14.30 A content notification can outrun the key that opens it

Found 2026-08-16 writing UC-A3.4's self direction live
([decisions 106](detail/decisions.md#106-a-notification-that-outruns-its-key-is-dropped-not-parked-2026-08-16)).
A notification whose decryption needs an nskey private the receiver has not yet
**filed** is **dropped and never retried**, while the private is filed a
fraction of a second later and the envelope stays on the atServer for
`envelopeTtl`.

**Cause, measured 2026-08-17.** The push is built and on time: approval conveys
the private (`EnvelopeEnrollmentConveyance`), and the receiver reads and deletes
both of its `__ssenv` envelopes. What is missing is the **wait** — `AtClientImpl`
fires `unawaited(_pqBootstrap!.startup())`, and
`PqClientBootstrap._collectConveyedKeys` (*"the only route by which a conveyed
nskey private reaches the keyfile"*) is that startup's second step. A client is
handed to its caller before its conveyed privates are filed. Drop at `12.703`
with `no nskey private held`; the ring's read-miss self-heal fired at `12.819`,
**116 ms too late**.

✅ **RULED 2026-08-17 (gkc), and BUILT** — see
[106.5](detail/decisions.md#1065-ruled-park-and-re-drive-not-readiness-at-the-hand-back-2026-08-17).
Direction 2 was not taken on its own: awaiting `startupComplete` closes only the
startup window, and a private conveyed while the client is already running still
races.

**What shipped.** `NskeyPrivateUnavailableException` carries
`(owner, namespace, nskeyKid)` so the park has a key that is not a message
string; `SignalsPrivateFiling` — implemented by `PublishedNskeyKeyRing`,
emitting from `NskeyPrivateFiling` **after** the material is readable — is what
releases it; `CryptoConfig` now carries the `keyRing` so the notification
service can reach the signal without depending on which providers are
registered. The park is bounded by `maxParked` and `parkTtl`, and every
eviction logs at `warning` naming the notification, because a held message
nothing re-drives is the same data loss with a longer fuse.

Unit cover: `notification_park_test.dart` — five rows, including the two
controls that keep it honest (a failure no filing can fix is dropped rather
than parked, and a filing for a *different* generation releases nothing).
Removing the park reddens three of them, each quoting its own reason.

**Four vacuous live attempts preceded the proof below, and they are kept because
each one is a trap worth not re-entering.** ⚠️ This paragraph used to end "Not
proven live, and a live proof needs something that does not exist yet" — that
was true when written and is now false; the whole chain is proven live, further
down. What the attempts establish:

1. **Minting the nskey *after* the enrollments** — intended to leave the
   receiver without the private. It leaves the *sender* without a published
   nskey too, so the send falls back to `legacy`, the receiver opens it
   trivially, and the run is green with the park never entered.
2. **Minting before, and not awaiting the receiver's `startupComplete`** — the
   originally measured shape. Still green with `parkedTotal == 0`: the test's
   own positive control (waiting for the monitor's stats notification to prove
   the monitor is live) takes seconds, and the receiver's startup finishes
   inside it. **The setup closes the very gap the test exists to open.**

The window is ~116 ms and sits between an `unawaited` startup's second step and
a notification, so no arrangement of ordinary test setup reliably lands inside
it. ⚠️ **Both runs would have been recorded as live proof but for
`NotificationServiceImpl.parkedTotal`**, a cumulative counter added precisely so
that "it arrived" cannot be mistaken for "it was parked and released".

3. **A `holdBeforeStore` seam on `NskeyPrivateFiling`**, so the window is held
   open rather than raced. ⚠️ This entry used to end "reverted unexercised …
   committing it would have added a test affordance to production crypto that no
   test uses". It **was** reverted at the time, for that reason — and once the
   `legacy` cause below was found it went back in and is now exercised by the
   live row (`nskey_private_filing.dart`, used at the live test's hold). The
   seam is in the tree; only the attempt that could not use it was discarded.
4. **Reordering so the receiver enrols before the second namespace is minted
   and the sender after** — on the hypothesis that `currentPublic` being
   local-first hid the new namespace from the sender. Also still legacy.

✅ **THE PARK IS PROVEN LIVE**, in
`tests/at_functional_test/test/nskey_park_and_redrive_live_test.dart`. A real
notification, sealed `at/nskey/XWING/AES/GCM` to a generation the receiver
genuinely does not hold, is **held rather than dropped**:

```
Parked notification @alice🛠:parked….nskeyparkb…
```

The window is made deterministic by `NskeyPrivateFiling.holdBeforeStore`, a
test-only hook: the race is ~116 ms wide and four earlier attempts to catch it
by timing all passed while never entering the park.

⛔ **What made those four vacuous, so nobody repeats them.** The era default is
`readsNskeyWritesLegacy` — it reads the nskey path and **writes legacy** — so a
`notify` that does not pass `cryptoProviderId: symmetricAesGcmCryptoProviderId`
goes out legacy and the park is never reached. UC-A3.4's test passes it on one
line. Four live runs were spent not reading that line; one grep would have
answered it. The other dead ends: minting the nskey after the enrollments
(starves the sender too), and installing the hold after the second namespace is
minted (the receiver has already filed by then).

**Two real defects fell out of the live work, both invisible to unit tests:**

1. **The filing signal resolved the wrong config.** `_listenForFilings` read
   `getPreferences().crypto.keyRing` — the *raw* preference. An app that names
   no config gets the era default, whose ring the PQ bootstrap supplies, so the
   read found null and the service silently subscribed to nothing. Now via
   `CryptoConfig.forClient`, re-attempted at park time because the bootstrap
   wires the ring asynchronously. Unit tests set `crypto` explicitly, which is
   the one case where the raw read happens to work.
2. **Every client held TWO `NskeyPrivateFiling` objects.**
   `collectConveyedKeyMaterial` built its own unconditionally, so the object
   that actually files conveyed privates was not the one the ring exposes.
   Harmless while filing was write-only — both wrote the same keyfile — but the
   moment a filing gained an observable event, the emitter was unreachable.
   Measured: `hasListener=false` on the announcing object while three clients
   had each subscribed successfully to a different one. The bootstrap now passes
   `ring:` through and the sweep files through the ring's filing.

✅ **THE WHOLE CHAIN IS PROVEN LIVE.** The run shows it end to end:

```
Parked notification @alice🛠:parked…
handleRequest kind=request          (the holder sees and answers the ask)
Filed the nskey private nskeyparkb…:__nskey.b195…
re-driving 1 parked notification(s)
```

and the notification is delivered **decrypted**. Getting there took three more
defects, none of which a unit test could reach:

1. **`PairwiseSecretSharing.startListening()` had no production caller**, and
   `_handleRequestPayload` — which answers another enrollment's request — is
   reachable **only** from `sweepOnce`. So a client's only sweep was the one at
   its own start, a request arriving later was seen by nobody, and **no
   read-miss self-heal could complete for anyone**. `PqClientBootstrap` now
   starts the listener and `stop()` tears it down.
2. **A declined request returned silently.** A holder that refused logged
   nothing, so "nobody answered" was indistinguishable from "everybody
   declined". Now `warning`, naming both sides. Fixing the instrument first is
   what made the next step findable.
3. **The read-miss heal asked and never filed the answer.** This is the one that
   mattered. `_askForMissingPrivate`'s dartdoc claimed *"the answer is filed by
   the arrival path so a later read finds it"* — and **there is no such arrival
   path mid-session**: nothing subscribes to `receivedSecrets` to file an nskey
   private, and `NskeyPrivateFiling.filePending` says so itself (*"a private
   that arrives after this runs is filed at the next start"*). Two dartdocs in
   one subsystem contradicted each other and the ring's was wrong. The heal now
   waits for the answer and files it, exactly as the startup path already did.

⛔ **What made four earlier live attempts vacuous, so nobody repeats them.** The
era default is `readsNskeyWritesLegacy` — it reads the nskey path and **writes
legacy** — so a `notify` without
`cryptoProviderId: symmetricAesGcmCryptoProviderId` goes out legacy and the park
is never reached. UC-A3.4's test passes it on one line. Also dead: minting the
nskey after the enrollments (starves the sender too), and installing the filing
hold after the second namespace is minted (the receiver has already filed).

The window is made deterministic by `NskeyPrivateFiling.holdBeforeStore`; it is
~116 ms wide and every attempt to catch it by timing passed while never entering
the park. `parkedTotal` is asserted so a run that wins the race cannot pass
quietly.

### 14.31 A refused watermark write permanently disables the monitor

`Monitor.stayConnected` calls `getLastNotificationTime()` **before** issuing
`monitor:`, and its first-call branch **writes** a seed record
(`local:lastreceivednotification.<ns>@<atSign>`). Under
`disallowLegacyEncryption` that put throws `LegacyEncryptionRefusedException`,
the exception escapes to the connect handler, and the monitor closes and
retries with backoff — **forever**. The client is silently deaf. The same
refusal hits `lastreceivedservercommitid`, the sync watermark.

That these writes are refused is **already known and owed to R-2** —
`ReleasePosture.postQuantum()`'s own dartdoc names "the sync and notification
watermarks" among them. What is new is the blast radius: one refused internal
write does not fail one write, it takes the notification listener out
altogether.

**Measured** on `nskey_self_notify_live_test.dart` at `56f69577a`, three arms,
same rig:

| arm | `refusing to encrypt` | test |
|-----|----------------------|------|
| both enrollments `migration` | 0 | pass |
| receiver `postQuantum` | 10 | pass |
| both `postQuantum` | 18 | fail |

⚠️ The receiver-only pass is timing luck — ten refusals happened in it too. It
is not evidence that one PQ client is safe.

⛔ **Not PKAM**, which is where three earlier guesses went. Every enrollment
authenticates `rsa2048` under both postures, with no signing-algorithm
resolution warnings: `signingAlgoOf` prefers the key-material resolution, and
the posture moves the *signing* key, never the authentication key.

✅ **DONE 2026-08-17.** It was six related defects, not one, and the diagnosis
above named the symptom rather than the cause. Ruling
[107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17)
carries the measurements; what shipped:

1. **A `local:` record no longer goes through the shared-data crypto path.**
   `_putInternal` and `PutRequestTransformer` skip it on `atKey.isLocal`. Such a
   record is never synced and the keystore encrypts it at rest, so value-level
   encryption protected nothing — while every post-quantum provider declines a
   local key, making *every* local write a legacy write by construction.
2. **`disallowLegacyEncryption` exempts `isLocal`.** It was refusing a provider
   **id**, not an exposure: for these keys "legacy" is `SelfKeyEncryption`,
   AES-256-CTR under a key that never leaves the device. A *synced* self key
   reaches the same class and is deliberately still refused.
3. **The SDK's own watermark writes pass `shouldEncrypt = false`** — the third
   layer, matching how the refusal is already checked at both selection and
   encryption time.
4. **`Monitor` no longer dies from it.** The watermark read has its own guard
   rather than sitting inside the connect `try` alongside four other
   operations, and a connect failure that is not a `SocketException` logs at
   `warning`, not `info`.
5. **The sync watermarks are guarded, and no longer mask.** The pull cursor is
   written in a `finally`, where a throw *replaces* the in-flight exception —
   so a failed cursor write was reported instead of whatever broke the sync.
   Extracted as `persistPullCursor`, whose contract is that it never throws.
6. **The notification watermark drops the payload and the metadata blob.** All
   twelve fields were stored and one is read. Older records still read back
   unchanged, so nothing migrates.

**Rails at the fix:** at_client unit **1386 (2 skipped)**, `dart analyze lib
test` exit 0 / 351 info, `dart analyze test` in `at_functional_test` exit 0 /
193 info. Twelve new tests, each with its break-it mutation run and confirmed
red *for its own stated reason*.

⚠️ One of those mutations found a defect in the tests rather than the product:
guarding `setAndGetSkipDeletesUntil` made a **stub-arity mismatch invisible** —
`sync_service_test.dart` stubbed `put(any(), any())` while production had begun
passing `putRequestOptions:`, so mocktail returned null, the write failed, the
new guard swallowed it, and the test reported success while persisting nothing.
It now verifies the call and its arguments.

⚠️ **This section used to claim a second half was still owed** — "namespace-less
keys that are not local, a legacy recipient's `shared_key.*` most obviously, are
still refused under the posture". That was wrong: nothing routes a
`shared_key.*` through the refusal, so it can never be refused. Closed as
[14.33](detail/implementation-plan.md#1433-closed-the-shared_key-refusal-was-never-reachable).
The one namespace-less write that genuinely is refused is
[14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given).

### 14.32 A `primary` client's ML-DSA signing key is not visible to its verifiers

An approver built `postQuantum` (so `rollout2`, `inUseSigningAlgorithms =
{mldsa65}`) conveys correctly — both `__ssenv` envelopes are written — and the
receiving enrollment refuses every one of them:

```
the envelope is signed under "ML-DSA-65" and the published _apsk advertises
"rsa2048" — no algorithm in common, so there is no signature here this key
can check
```

`waitForApproval` then times out at 30s with *"No conveyed apkamSymmetricKey
arrived … the approver is running a client that does not convey"*, which names
the wrong side: it conveys, and what it wrote cannot be verified.

The approver is the atSign's own client, so it has **no enrollment id** and
mints under the `primary` pseudo-enrollment. It does mint and does try to
publish — `Minted mldsa65 signing key(s) for primary; publishing before
filing`, then `publishPublicSigningKey: what is published is not what this
client holds - republishing` — and `enroll:update` is sent **zero** times,
correctly, because there is no enrollment record to update. Yet a verifier
reading `public:_apsk.primary.a.__e@alice🛠` still saw `rsa2048` throughout the
30s.

⛔ **The transport question is ANSWERED, and the answer is no — do not
re-derive it.** This entry used to say the one open question was "by what
transport does the `primary` republish reach the atServer? A local-first put
reaches it only when sync gets round to it … a race by construction." Read
2026-08-17: **every leg of this path is remote-first.**

| leg | where | routing |
|-----|-------|---------|
| the writer's pre-read | `apkam_signing.dart:56` | `useRemoteAtServer = true` |
| the republish itself | `apkam_signing.dart:73` | `useRemoteAtServer = true` |
| all five verifier reads | `pq_signing_chain.dart` 224, 272, 403, 465, 637 | `useRemoteAtServer = true` |

So there is no value-and-pointer-on-different-transports race here, and no fix
should be designed around one.

**Also ruled out by reading, not by measurement:** signing and advertising
cannot drift on this path. `EnvelopeSigning.wrapAndSign` resolves
`await signingKeys` (`envelope_signing.dart:56`) and the advertisement is
composed from the same getter, which is what `signingKeys`' own dartdoc claims
("what signs and what is advertised are one rule and cannot drift apart").

**The cause, measured 2026-08-17 — it is a CLOBBER, in order, both writes
remote.** The arm was re-run with the approver built `postQuantum`, and the
atServer's own log for `@alice🛠` was read rather than the client's account of
it. The record starts absent (`AT0015 … does not exist in keystore`) and then
takes **four** updates:

| # | what the update wrote |
|---|-----------------------|
| 1 | a bare RSA public key (`MIIBIjANBgkqhkiG9w0B…`) |
| 2 | a bare RSA public key |
| 3 | **`{"v":1,"keys":[{…,"alg":"mldsa65",…}]}`** — the mint's republish |
| 4 | **a bare RSA public key** — overwrites 3 |

So the ML-DSA advertisement *is* published, and is then overwritten by a later
writer with the RSA fallback. A remote read taken **after** both republishes
returned the bare RSA key, which is what the verifier then refuses against for
the whole 30s. Nothing here is a transport problem; the final state is simply
the wrong value.

**The mechanism, confirmed by instrumenting `publishPublicSigningKey` and
re-running.** Every call logged what it held and what it was about to write:

| # | caller | `heldSigningKeys` | `value` passed in? | writes |
|---|--------|-------------------|--------------------|--------|
| 1 | `AtClientSecretSharing` | `[]` | no | bare RSA |
| 2 | `AtClientSecretSharing` | `[]` | no | bare RSA |
| 3 | `SigningKeyMinting` | `[]` | **yes** | **`mldsa65` JSON** |
| 4 | `AtClientEnvelopeSigner` | `[]` | no | bare RSA |

**`heldSigningKeys` is empty at all four**, so the minted signing key never
reaches the keyfile for `primary` at all. `signing_key_minting.dart:287` — the
only call that passes `value:`, and guarded by `atLookUp?.enrollmentId == null`
— advertises the minted key by handing the value in directly, which is what
"publishing before filing" means. Every other caller composes from
`publicSigningKeyValue`, reads an empty keyfile, falls back to the APKAM
authentication key (RSA), and publishes that over the mint's advertisement.

⛔ **STOP — this is [ruling 102](detail/decisions.md#102-an-_apsk-fallback-value-never-replaces-a-real-advertisement-2026-08-15),
already measured and already ACCEPTED.** `_publish`'s own dartdoc
(`signing_key_minting.dart` ~252) describes this exact sequence — "a concurrent
`publishPublicSigningKey` … sees no signing key, falls back to the APKAM
**authentication** key, and overwrites: measured, a PQ-native enrollment's
ML-DSA array replaced by a bare RSA string" — and records that **three guards
against it were built and all three broke the live enrollment path.** It warns
anyone tempted to try a fourth that "never drop an advertised key" cannot be
stated over `public:_apsk.primary.a.__e`, which no single client owns.

**So the record-level guard is a re-derivation. Do not build it without
re-opening 102.**

⚠️ **What is NOT yet established, and what an earlier version of this entry
wrongly asserted.** It claimed "it is not a timing window … the keyfile is empty
for the whole run". The evidence does not support that: `_file` **is** called,
at `signing_key_minting.dart:167`, immediately after `_publish`, so the empty
keyfile at all four calls is equally consistent with all four falling *inside*
the publish-before-file window — which is exactly what 102 describes. The
timeline is 20 ms wide:

```
07.117  Minted mldsa65 … publishing before filing
07.119  SigningKeyMinting   held=[]  -> writes mldsa65 (value: override)
07.155  … republishing
07.175  AtClientEnvelopeSigner held=[]  -> writes bare RSA
07.200  … republishing
```

**Ruling 102 has been re-opened on this evidence** — see
[102.1](detail/decisions.md#1021-the-race-is-measured-and-the-price-it-was-accepted-at-was-wrong-2026-08-17).
Two of its sentences were false and are corrected there: the race **is**
measured, and reaching it needs **no** application call racing `startup()` —
the ordinary approver flow does it every run. More importantly the *price* was
wrong: 102 accepted "one process lifetime of refused envelopes", where the
measured cost is that **a `postQuantum` approver cannot approve an enrollment
at all**.

⛔ **That does not revive the three guards.** Guard 3's finding stands: the
demotion rule cannot be stated over `primary`, a record no single client owns.

✅ **The filing works, so this is 102's window and nothing else.** Logging
`heldSigningKeys` immediately after `_file` returns gives `[mldsa65]`, with the
mint's `io` and `atClient.atKeysIo` the same instance. The keyfile does hold the
post-mint state; `AtClientEnvelopeSigner` simply read before the filing
completed.

✅ **DONE 2026-08-17 — fixed by serialising this process's `_apsk` writes**,
ruled and built as [102.2](detail/decisions.md#1022-the-in-process-window-is-closed-by-serialising-the-writers-2026-08-17).
`serialiseApskWrite` chains every `_apsk` write one client makes, and the mint
holds it across publish, file and retire together, so a writer arriving mid-mint
composes after the filing and finds nothing to change. It states in-process-only
and nothing more — a second client in another process is still 102's accepted
window. Re-entrancy is handled by splitting `publishPublicSigningKey` (acquires)
from `publishPublicSigningKeyLocked` (does not).

**Proven live on the arm that had never passed:** updates to
`_apsk.primary` go 4 → 2, the final value goes bare RSA → the `mldsa65` array,
`no algorithm in common` goes 2 → 0, and the test goes fail → pass. Unit cover
in `apsk_write_serialisation_test.dart`, whose ordering test reddens on the
exact interleave when the lock is removed.

⚠️ This is **not** [14.31](#1431-a-refused-watermark-write-permanently-disables-the-monitor).
That one is a refused internal write killing the monitor; this one is an
advertisement a verifier cannot see. Both surfaced from the same posture and
they have nothing else in common.

### 14.35 `NotificationService.send()` throws away the namespace it was given

`send()` takes a namespace as a parameter, builds a key string from it, and then
recovers the namespace by re-parsing that string
(`notification_service_impl.dart:578`):

```dart
final String key = '$to:$namespace$atSign';
final AtKey atKey = AtKey.fromString(key);
atKey.metadata.namespaceAware = false;
```

`AtKey.fromString` splits at the last dot, so the round trip is lossy in two
different ways. Measured, both arms, against a client under the postQuantum
posture:

```
send(namespace:"wavi")       => THREW LegacyEncryptionRefusedException
send(namespace:"buzz.wavi")  => selected at/symmetric/AES/GCM
```

A **single-segment** namespace parses to `namespace = null`, so every
post-quantum provider declines it (`canHandle` is `!isLocal && namespace != null
&& namespace.isNotEmpty`), the fallback is legacy, and the flag refuses it. A
**dotted** namespace parses to `key = "buzz", namespace = "wavi"` — it seals,
but to an nskey scoped to `wavi` rather than to the `buzz.wavi` the caller
named.

`send()` is the only write path that can reach this, because it is the only one
that bypasses the namespace defaulting every other path applies before
encrypting — `at_client_impl.dart:981` and `:1252`
(`atKey.namespace ??= preference?.namespace`) and
`notify_request_transformer.dart:122` (`ak.namespace ??= atClientPreference.namespace`).
`send()` encrypts inline and hand-builds its own `notify:` command string, so it
touches none of them. `AtRpc` sets `..namespace = baseNameSpace` explicitly and
goes through `notify()`, so it is unaffected.

**The fix, ruled by gkc 2026-08-17: the parameter is `<id>.<namespace>` and is
poorly named — that is the root of it.** The id is the first segment and the
namespace is the remainder, so `send()` splits at the **first** dot and sets
both `AtKey` fields itself instead of letting `fromString` do it. `namespace` is
deprecated in favour of `idAndNamespace`; a name with no interior dot, or with
either half empty, throws `ArgumentError` at the call site.

⚠️ **An earlier draft of this row recorded a one-line fix — "set
`atKey.namespace = namespace`" — and that was WRONG.** It would have broken
every `send()` that works today. The ciphertext binding is computed over
`'${atKey.key}.${atKey.namespace}'`, deliberately split-invariant so writer and
reader agree, and setting only the namespace changes the joined name. Measured:

```
                     sender          receiver (parses the wire)
today                "buzz.wavi"     "buzz.wavi"        match
+ namespace only     "buzz.buzz.wavi"  "buzz.wavi"      MISMATCH — nothing decrypts
+ namespace, key=""  ".buzz.wavi"    "buzz.wavi"        MISMATCH
first-dot split      "a.b.c"         "a.b.c"            match
```

The first-dot split holds for every case tried (`wavi`, `buzz.wavi`, `a.b.c`,
`id.foo.bar.my_app`) precisely because the join is split-invariant: the sender
cutting at the first dot and the receiver at the last produce the same name.
The wire key is unchanged, so this is not a cross-version break; what changes is
that the content key is conveyed at the level the caller named, and a receiver
that has not yet got it parks and re-drives
([14.30](#1430-a-content-notification-can-outrun-the-key-that-opens-it)).

`send()` is public, documented and not deprecated, and two example programs use
it (`example/bin/notifications.dart`, `example/bin/dockerstats_publish.dart`) —
both with dotted namespaces, so both take the wrong-scope arm rather than the
refusal.

### 14.36 `send()`'s command is hand-rolled where a tested builder exists

`send()` writes its own `notify:` command into a `StringBuffer` rather than
using `NotifyVerbBuilder`, which is what every other notification path goes
through. It is the duplication that let
[14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given)
happen: the builder path resolves a namespace before encrypting, and `send()`
never reached it.

The swap is nearly free, but not free. Measured, same inputs:

```
hand-built today   notify:id:X:ttln:900000:isEncrypted:false:@bob:a.b.c@alice:payload
NotifyVerbBuilder  notify:id:X:notifier:SYSTEM:ttln:900000:isEncrypted:false:@bob:a.b.c@alice:payload
```

Byte-identical **except** `:notifier:SYSTEM`, which `buildCommand` writes
unconditionally. So this is a wire change, not a refactor, and it does not ride
along with a behaviour fix — it gets its own commit and its own functional-pack
run. The argument that it is safe (every `notify()` call already sends that
token, so the atServer sees it constantly) is an argument, not evidence.

⚠️ **`useAtKeyToString = true` is required.** With it false the builder writes
`:${atKey.key}`, and since 14.35 the name is split across `key` and `namespace`,
so the wire key would become `@bob:a@alice` — measured. `atKey.toString()`
yields `@bob:a.b.c@alice` under either `namespaceAware` setting.

**Built 2026-08-17.** The command is pinned as a raw literal rather than by
`contains` fragments — a wire shape is frozen, and an intended change has to
edit the pin, which is the review. A `contains` check would not have noticed
`:notifier:SYSTEM` arriving.

⚠️ **`send()` had NO live coverage at all, in either direction** — the pack's
168 tests never called it, so the first pack run after this change proved only
that nothing else regressed. `:notifier:SYSTEM` being safe rested on every
`notify()` already sending it, which is an inference, not an exercise of this
path. `atclient_notify_test.dart` now drives `send()` live: it asserts the
stored notification's key is the *whole* name (the wire half, which a builder
writing only `atKey.key` would truncate) and that the body arrives decrypted at
the recipient.

⚠️ **The architecture guard had to move with it, and the direction matters.**
`architecture_guard_test.dart` required `notification_service_impl.dart` to
mention `toAtProtocolFragment`, which the file no longer does — the builder
calls it. Keeping that assertion would have forced the hand-rolled command back,
so the guard now asserts the file does **not** contain `'notify:id:`. That is
what the guard was always for: not the presence of a name, but the absence of a
rival serializer. Verified against the previous commit, where the pattern
appears once.

### 14.34 An unexplained intermittent in `self_enrollment_retrofit_live_test.dart`

One full-pack run on 2026-08-17 came back **166/167**: the test timed out after
40 s at `await firstNotification`. **Five pack runs were made that day and only
that one failed** — the others were 167/167 and 168/168 ×3 — and the file passes
alone.

⛔ **Not a flake, and not fixed.** Nothing explains it. Five observations bound a
rate, not a kind, and "it was green before" is weak in the other direction too:
the 167/167 baseline it is measured against was itself a single run. Record any
further occurrence with its numerator and denominator rather than re-classifying
it.

**If it recurs,** the bisect point is `0668cf91d` — code there is 14.31's
local-key fix without the `_apsk` write serialisation, so green at that commit
would pin it on the serialisation.

### 14.29 The residuals 14.25 surfaced

**Two** project entries owe work the D1 burn-down never listed — it was three
until 2026-08-18, when B-1's pair turned out to have shipped. Found 2026-08-16
by reading all nine against the tree ([14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)).
They are collected here because a residual left inside a project entry is
invisible to anyone working the TODO table.

- **SS-2 — the atServer's `__ssenv` behaviour.** It does not exist server-side
  at all, so DEP4's update-put auto-notify is unbuilt — but it is **deferred,
  not owed**: [the 2026-08-03 ruling](detail/implementation-plan.md#ss-2--substrate-wired-into-atclient--server-wake-up-key-package-in-request-new-device-conveyance-only--at_secondary_server-at_client-at_auth-at_commons--l--2085)
  took DEP4 off SS-2 once the correctness argument behind it was withdrawn, so
  what is left here is a pure optimisation and `sendWakeUpNotification` stays
  `true` until it lands. ⚠️ Needs parity across every atServer implementation
  in the same sweep, which is a clean starting state rather than unfinished
  homework: `__ssenv` is a zero in all three implementations, so none has a
  divergent version to reconcile. ⚠️ **Re-derive against all three, not just
  the first** — this named only `at_server` until 2026-08-18, which answers a
  question about one repo:
  `git -C ~/dev/atsign/repos/<repo> grep -c "__ssenv"` for `at_server`,
  `java_at_server` and `at_java`. Zero in each as of 2026-08-18, each run
  beside a control that matched, since an unvalidated grep and a true absence
  print the same nothing.
- **B-1 — none left of the two.** ✅ Both closed since, and re-verified
  2026-08-18. This bullet used to read *"two left: everything beyond envelope
  delivery (`pushSecretToNames…`); and UC-A3.4's self direction, owed rather
  than blocked since `ConcurrentClients` landed"*
  ([#2093](https://github.com/atsign-foundation/at_client_sdk/issues/2093)).
  UC-A3.4's self direction is built and **live-green** —
  `nskey_self_notify_live_test.dart`, "a self notification reaches a second
  enrollment and decrypts", passing in the functional pack. The substrate's
  pull flow is driven live by `nskey_park_and_redrive_live_test.dart` and
  `signing_root_pull_two_enrollments_test.dart`, and **eight** functional
  files now run two real enrollments — so the "waits on SS-2" clause on the
  live-coverage row was wrong as well as the count: two enrollments never
  needed `__ssenv`.
  ✅ **The fixture blind spot is closed** (2026-08-16):
  `buildRemoteBackedMockClient` takes an optional `localData`, and with it a
  local-first read of a key only the atServer holds misses instead of
  succeeding. Opt-in, because the nine callers that predate it specify the
  single-store default.
- **S-3 — two, both small.** This said **three**; the migration test exists.
  `at_keys_test.dart` covers the only N-1 there is — `AtKeys.supportedVersion`
  is still `1`, so the predecessor is the unversioned legacy document, and it
  is pinned three ways: legacy fallback on a versionless file, no version
  stamped onto a file that gained only an atsign, and a field-for-field
  round trip. What remains: a keychain round-trip on a real device,
  **blocked** because this repo has no `integration_test` harness and
  at_client_flutter's tests mock the platform channel; and
  `LocalKeystoreAtKeysIo`, still "not needed at this time" — named in four
  docs and in no source file.

⚠️ **None of these blocks D1's remaining sequence**, which is why they were
survivable as residuals. The B-1 fixture item was the one with teeth — a fake
that cannot distinguish local from remote is exactly the shape that let the
nskey mint read local storage — and it is now closed.

**Re-read against the tree 2026-08-18**, two days after they were written, and
**three of the six had shipped without anything striking them.** Only SS-2
survives intact: `git -C ~/dev/atsign/repos/at_server grep -c "__ssenv"` still
matches nothing, with a positive control run to prove the grep reaches the
repo. That ratio is the finding — a residual parked inside a project entry
falsifies quietly, because the work that closes it is filed somewhere else.

### 14.18 The remaining D1 initial-development sequence

Ruled 2026-08-11 by a walk through every open item
([`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)).
This is the **order**, not the inventory — each row points at the entry that
holds the detail. **D1 initial development ends at step 34**, when the stacked
PRs are merged; publishing and R-2 follow it.

**Stage 0 — scaffolding.**

| # | Work | Where | State |
|---|------|-------|-------|
| 1 | Drop at_server's `at_commons` override; delete the `at_commons-apsk-1` tag | at_server | **DONE 2026-08-11.** Override gone from both files, `pubspec.lock` resolves hosted 5.14.0, tag deleted local+origin. **[at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744) is MERGED** — corrected 2026-08-13; this row and step 2a both said "open" for a week while `5bc3618a` had become an ancestor of at_server's `origin/trunk`, and the tags `c3.16.0` and `c3.16.1` both contain it. ⚠️ **at_server's 210/210 is still stale** and must be re-earned. `origin/trunk` was `c16f32b0` when this row was written on 2026-08-13 and is `fdb78568` as of 2026-08-14 — re-derive it with `git -C ~/dev/atsign/repos/at_server log --oneline -1 origin/trunk` rather than citing either, since this row records a moving value and nothing here goes red when it moves |
| 2 | Run at_client_sdk's functional pack for the two never-run keyId-shape files | at_client_sdk | **DONE 2026-08-12.** Both pass: `pq_native_onboard_live_test.dart` (UC-A1.1) in the functional pack, and `pq_native_onboard_test.dart` in at_onboarding_cli's pack, both against `at_virtual_env:local`. The run also surfaced the `_apsk` seam break below — 16 of 19 failures, one cause |
| 2a | **The `_apsk` composer moves client-side** — at_server#2744 merged, so the atServer publishes only what a request sends and composes nothing. The client sent nothing, so no `_apsk` existed at approval and every advertised key package was rejected. `EnrollVerbBuilder`/`EnrollParams` gain `apsk` (the array) and `apskLegacy` (the bare RSA string); at_auth composes one or the other at all three submit sites; `parseApskValue` reads the array; the never-published tagged form is deleted | at_client_sdk | **BOTH HALVES DONE.** Client half 2026-08-12, functional pack 127/19 → 143/3. **The atServer half is MERGED too** — corrected 2026-08-13, having been listed as owed after it landed: at_server `6a86fbcc` "feat(at_secondary_server): honour apskLegacy, and bound the whole record" went in via [at_server#2746](https://github.com/atsign-foundation/at_server/pull/2746) (merge `b4ea7cf2`), is an ancestor of `origin/trunk`, and `at_secondary_server` is 3.16.1. ⚠️ **Do not rebuild it.** ✅ **The exercise this row still owed is discharged as of 2026-08-14**, on both arms and against the local image that carries the server code: the **request** arm by rollout-1 enrollments in the matrix, where UC-G1.14 has a released at_client 3.14.0 reader fetch that record and parse it with `RSAPublicKey.fromString` — which succeeds only on the bare form — and the **`enroll:update`** arm by B4's `apsk_server_side_test.dart` row "a healed enrollment advertises its signing key in the bare form", which is the only thing that has ever driven `apskLegacy` on an update — it had been sent solely on the enrolment request. That row is proven discriminating: with the client-side fix reverted it is the only failure of 164 |

**Stage 1 — one envelope shape, one key vocabulary, then the `_apsk` reader
half. Nothing blocks it; start here.** Steps 3–5 are ordered so each shrinks
the next: deleting v1 removes wrapper branches the vocabulary would otherwise
have to carry, and the vocabulary is where `status` is defined before step 5
builds on it.

| # | Work | Detail |
|---|------|--------|
| 3 | **DONE 2026-08-12 — one envelope shape, RFC 7515 general serialization**, `{payload, signatures:[{protected, signature}]}` with `{alg, kid, v}` in each `protected`. Deleted `signedEnvelopeVersion`, `jwsEnvelopeVersion`'s flattened form, `envelopeVersionOf`'s dispatch, the `wrapperFields` ternary in `ApkamSignedAdvertisedKeys.verify`, and `envelopeVersion` as a `ReleasePosture` axis. Also took `hashingAlgo` off `signEnvelope` — `alg` names the hash, so nothing unsigned selects a routine — and retired UC-C1.3, the rollout's envelope axis, which had nothing left to drive. The `.mjs` adjudicator moved `flattenedVerify` → `generalVerify`; vectors regenerated at `test/vectors/jws_envelope.json`. **Found en route:** `publishPendingLink`'s already-published check compared a top-level `['signature']` the envelope does not have, so `null == null` matched every time and a different link conveyed later was silently never published | [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) ruling 1, **superseding [91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11) ruling 12**'s bespoke container |
| 4 | **DONE 2026-08-13 — ruling 2 landed, so all of step 4 is complete and step 6 is unblocked.** Ruling 2 in three commits: `6462ae786` (the advertisement becomes `{v, createdAt, keys:[{use, alg, pub, kid}], suites}` with one `toPayload`/`fromPayload` codec replacing a map literal in `_mint` and a hand parser in `verify` 250 lines apart), `d28ef48a9` (a key that is not its algorithm's length is refused — a kid is the digest of whatever bytes are carried, so it matched a forged key as readily as a real one), `69449603e` (the reader skips entries it has no KEM for and picks the strongest it can use, which has to ship before any writer emits a second key). **Three things the ruling got wrong**, all corrected in `decisions.md` 94: `_apsk` entries never carried `status`; `status` and `KeyEntryStatus` are deferred **entirely to step 5** so no dead field ships (gkc, 2026-08-13); and at_auth cannot reach `PackageKey` because at_client depends on at_auth, so one vocabulary means one **wire spelling** across two Dart types. `createdAt` was added for symmetry with `KeyPackage`; `v` stays 1. Rails: at_client 1188/1188, functional 146/146. One key-entry vocabulary across all three advertising records — `{use, alg, pub, kid, status?}` inside `{v, keys:[…], suites}`. **Landed 2026-08-12:** ruling 3 (one kid function, at_auth's `publicKeyKid`, over the key's raw BYTES — `apskKid` hashed the base64 text and `nskeyKidOf` the material, and every kpid changes value); ruling 4 (`v`, `alg`, `suites` required, both `legacy*Suites` deleted); ruling 5 (one `SecretSharingAlgos.bestSuiteBetween`); **ruling 6** — `pq_envelope.dart`'s `pqSealToBase64`/`pqOpenFromBase64`, both taking `info` and `version` as **required** arguments and constructing neither, so there is nothing inside the shared code for the two substrates to converge onto. at_chops' `pqSeal`/`pqOpen` now require `info` too, which makes a shared binding a **compile error** rather than a convention — it was reachable before, because `info` was optional and `info ?? Uint8List(0)` made omission and empty the same binding. **Found en route:** the pairwise substrate had NO test that could fail on a converged binding — dropping the label from all three pairwise/enrollment call sites left the suite green at 1180/1180 — so the production-fed differential in `pairwise_secret_sharing_test.dart` was built first and proven by that same symmetric mutation, which now turns exactly one test red. **Still owed: ruling 2** — the nskey advertisement gains a `keys` list and adopts the shared spelling | [`decisions.md` 94](detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11) — ⚠️ **before step 6**, or that parser becomes the third hand-rolled codec for one shape |
| 5 | **DONE 2026-08-13 — the `retired` key path, in three commits.** `6a5eac838`: `PackageKey` gains `status`, a `KeyEntryStatus` of `active` or `retired`, and `bestKeyFor` on both a key package and an nskey advertisement passes a retired key over, so `kpid` is the *active* enc key's kid. Emitted only when retired — absent already reads as active — and an unrecognised value reads as retired, the one reading that cannot make a build use a key its owner withdrew. `f956b2146`: `PersistedApkamKeys` becomes `{encKeys: [PersistedEncKey]}` and `KeyPackageRegistration` expands, advertises and answers for every held key, with `encKeyFor(kid)` replacing `encSecretKey` and `heldKpids` listing every address. `f6fc3796e`: the sweep, the wake-up subscription and the sync listener cover every held address (`EnvelopeAddressing.regexForAny`/`sweepRegexForAny`), and `_consume` opens with the key the envelope names. **Three things ruling 9 got wrong or omitted**, all recorded in `decisions.md` 95: the sweep filter is a **fifth** consequence and the one that makes the other four reachable; the keyfile already records the status (`AtKeysMaterial.KeyPartStatus`, `AtKeys.retireKey`, and an `AtKeysAssurance` rule enforcing one active `publicEncapsulation` per enrollment and algorithm), so deriving it from `createdAt` was wrong; and `dead` material is not adopted at all. Rails: at_client 1210/1210, functional 146/146. **Nothing rotates yet** — the writer is step 16. ⚠️ app-facing: `PersistedApkamKeys` is what apps build in `loadApkamKeys`/`saveApkamKeys` | [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) rulings 6–9 — without the plural holding the field is decorative. The **name collision** was settled 2026-08-12 (gkc) and landed as ruled: the per-entry wire value is a Dart `KeyEntryStatus`, and `KeyPackageStatus` — the reader's verdict on a whole package (`present`/`absent`/`rejected`/`unsupported`) — keeps its name. Nothing renamed |
| 6 | **DONE — mostly with step 2a, completed 2026-08-13.** `parseApskValue` reads the array **and** the released bare string, refuses a structured value advertising nothing it understands rather than guessing, and skips entries whose `use` or `alg` it does not know; `apsk_formats_test.dart` covers all of that plus "the array form is unmistakable to a bare-RSA consumer". Finished on 2026-08-13 by giving `ApskSigningKey` a `status` and having `apskSigningKeys` read it — **keeping** a retired entry, because this list is what verifies stored envelopes and a retired key is precisely what signed the older ones. `KeyEntryStatus` moved from at_client to **at_auth** in the same change so all three advertising records name one type, narrowing [94](detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)'s "one vocabulary cannot mean one Dart type" — that was true of a type living in at_client, and at_auth is the lower package. **Found by the re-verify:** `design.md` 9.3's JSON example omitted `kid`, which the reader requires, so the document the design showed is one every reader treats as empty and then refuses; corrected, and pinned. `advertised.first` and the singular `ParsedApsk` are steps 7–9's business, not a gap here | [`design.md` 9.3](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |
| 7 | **DONE 2026-08-13.** `SigningAlgoType.strongestFirst` + `strongestOf` in at_chops — purely additive (two statics on the existing enum; no member added, moved or renamed, so it does not touch the unresolved 3.6.0-versus-major question). Deliberately **not** declaration order: members are declared in the order they were added and reordering them is a wire change, so preference is a second statement. `mldsa65` first, categorically — the only member Shor does not break — then RSA-4096, `ed25519`, `ecc_secp256r1`, RSA-2048 by classical security level. Total on purpose: a partial order leaves the choice undefined for exactly the pair nobody thought about. **The tripwire is completeness, not just the literals**: a new `SigningAlgoType` left out of the order turns `test/signing_strength_test.dart` red, which is what stops it becoming silently unrankable. Wired straight into `parseApskValue`, which took `advertised.first` — the order entries arrive in is the *signer's* choice, so an enrollment advertising ML-DSA-65 beside RSA-2048 was verified against whichever it listed first | [14.17](#1417-signature-agility--complete) |
| 8 | **DONE 2026-08-13.** `requireAlg` is gone rather than rewritten: the algorithm is now *resolved* — from what the envelope's `signatures` and the signer's `_apsk` have in common, taking the strongest by `SigningAlgoType.strongestFirst` — and then its key is fetched, where before one advertised key was taken and the envelope was required to match it. Its refusal survives in a different form: no algorithm in common is refused naming both lists. `ParsedApsk` went plural (`keys`, `keyFor(algo)`; `signingAlgo`/`publicKey` survive as strongest-of getters), and the bare RSA form parses to a one-entry list so both published forms are one shape to the caller. The two JOSE `alg` switches — one on the sign side, one on the verify side — became one `_joseAlgFor`, since two would be two chances to disagree | ⚠️ an inversion, not an addition |
| 9 | **DONE 2026-08-13, with step 8** — the two do not separate: resolving the strongest shared algorithm *is* walking the entries. `verifyEnvelope` selects its entry by algorithm rather than taking `signatures.first`, verifies only that one, and refuses on failure with no fallback. **Found en route and fixed:** `signerEnrollmentId` reads `signatures.first.kid` while the verified entry is now chosen by algorithm, so the two could be different entries — append a signature under a stronger algorithm carrying another kid and a caller acts on a signer whose signature was never checked. `SignedEnvelope.fromJson` now refuses an envelope whose entries name more than one signer, which is a structural claim about this shape rather than a verify-time check. UC-G1.7 is covered for the first time, four rows | [`design.md` 9.4](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |

**A reader understanding no entry refuses outright** — no downgrade, no fallback
to a derivable legacy key ([`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11) ruling 2).

**Stage 2 — the unblocker. The writer half cannot start before this.**

| # | Work |
|---|------|
| 10 | **DONE 2026-08-13 — one resolver, not a materialised projection.** `AtKeys.authenticationFor(enrollmentId)` returns the AtChops and the PKAM algorithm, with typed material winning wherever the keyfile holds it for that enrollment and the flat fields answering only where it holds none; `authenticationAlgorithmFor` is the algorithm half, so a caller holding an injected AtChops does not build one `toAtChops` would throw on. `AtAuthImpl.authenticate` and `AtClientImpl._createAtChops` both move onto it. **Ruling 7 as written could not be built** and is amended in place ([`decisions.md` 91.3](detail/decisions.md#913-the-rulings)): filing a projected material makes `toJson` emit `version`/`atsign`/`keys` — the guard is `keys.isEmpty` and both stores stamp `atsign` first — which breaks the byte-identical legacy round-trip [91.4](detail/decisions.md#914-what-is-released-and-therefore-what-must-still-be-read) promises, and on a retrofitted keyfile the one-active-`privateAuthentication`-per-document rule refuses the add outright. Four shipping shapes hold nothing to project from: a pre-typed `.atKeys`, an `rsa2048` first onboard, an OTP enrollment, and an onboard handed its keys by the caller. **Found en route and fixed:** `_createAtChops` picked its keypair off the algorithm `_resolveSigningAlgoFromKeyMaterial` had recorded, and that records nothing when its own read throws — so a transient keyfile failure made a retrofitted client PKAM with the *flat* enrollment's key while its typed material sat in the same file. Its comment claimed it mirrored `AtAuthImpl`; it did not. Rails: at_auth 257/257, at_client 1218/1218 |
| 11 | ✅ **DONE 2026-08-13 — both halves.** ⚠️ This cell was labelled `PARTLY DONE` until 2026-08-18, five days after its own closing clause recorded the second half as done, and 15.2 said so in prose the whole time — a diagnosis is not a correction. **The wiring half.** ⚠️ **The nullability was never the problem, and the blocking claim was measured rather than inherited.** `apkam_signing.dart`'s dartdoc says sourcing from `AtKeys` "cannot land until every client has an `AtKeysIo` — today it is nullable and most apps supply none". Measured over the 22 repos on disk that depend on at_client: **0 of 22** supply one to a client and **0 of 22** use `fromAuthSession`, so the claim is TRUE — but the dominant cause is one SDK line, not app behaviour. `AtOnboardingServiceImpl.authenticate()` built a `FileAtKeysIo` for `AtAuth` and then created the client without it, so every `at_cli_commons` consumer (at_talk, sshnoports, noports-tools, at_demos, ogentic) inherited a source-less client. **Fixed:** `_initAtClient` takes the source and threads it to `setCurrentAtSign`. The injected AtChops still authenticates — this only gives the client the source for what AtChops cannot answer. ⚠️ **Deliberately NOT done: an `atKeysIo ??=` default on at_client_flutter's `AuthService.authenticate()`.** `AtAuthRequest`'s constructor already refuses a request with neither `atKeysIo` nor `atAuthKeys`, so the default could only ever fire when the caller supplied `atAuthKeys` — an app that loaded its own key material — and pointing it at a keychain that may hold another atSign's keys, or none, is a guess. The asymmetry with `onboard()`'s `??=` is correct: onboarding mints keys and needs somewhere to write them. ⚠️ **The null case is a tested, deliberate property**, not an oversight — `no_atkeysio_inertness_test.dart` pins that a source-less client performs zero PQ writes at startup, which is what protects the long-lived cicd atServers, and the e2e pack builds its clients through `setCurrentAtSign` directly so this change does not reach them. ✅ **DONE 2026-08-13, with step 12:** the signing half — `signingKeys` sources from `AtKeys` rather than reading the APKAM auth keypair out of `atChops`. Built once, as step 12's per-algorithm accessor |
| 12 | ✅ **DONE 2026-08-13.** `AtKeys.signingKeysFor(enrollmentId)` (at_auth) returns every active signing keypair the enrollment holds, one per algorithm, strongest first; `ApkamSigning.signingKeys` (at_client) is a `Future<List<ApkamSigningKeys>>` reading it through `AtClient.atKeysIo`. `ApkamSigningKeys` now carries its `algorithm` and `signEnvelope` takes it from there rather than a separate `signingAlgo` argument — a key and an algorithm arriving separately can disagree, and the resulting signature verifies against nothing. ⚠️ **Selection is by the keyId shape `sign:<enrollmentId>:<algo>:<n>`, NOT by the `privateSigning` role**: `PqSigningRoot` files the atSign-wide signing root under that same role with no enrollment id, so a role filter hands an enrollment a key that was never its own — the same defect shape as 14.19 item 6. Proven by mutation: selecting on the role turns two tests red. **The empty case answers with the APKAM authentication keypair**, which is what ruling 10 keeps in the `_apsk` array permanently, so the accessor is live from this commit rather than waiting on a writer, and `now`-posture envelopes stay byte-identical (the stored JWS vector re-signs to the same bytes). That also covers the source-less client, which is a deliberate tested property. Read per call, not cached: a cached copy goes stale the moment a rotation retires what it held. **The minting/filing half is NOT here** — `fileSigningMaterial` still has no production writer, and which algorithms to mint is the in-use set's decision, so it stays step 18. Rails: at_client **1228/1228** (2 skipped), at_auth **266/266** |

**Stage 3 — the `_apsk` writer half (rollout 2).**

| # | Work |
|---|------|
| 13 | ✅ **DONE 2026-08-13.** `apskAdvertisement` composes from a **list** of keys rather than one `(apkamPublicKey, signingAlgo)` pair, so a second algorithm's key can be advertised beside the first; `ApskSigningKey.forPublicKey` builds an entry and derives its `kid`, which is never a caller's to supply. `status` is emitted **only when retired**, so an advertisement that has never rotated is byte-identical to what the single-key composer wrote. The enrollment-request site still sends one key — at request time the enrollment holds nothing but its freshly minted APKAM keypair, and a second arrives by `enroll:update` (step 16) once step 18 mints one. **`publishPublicSigningKey`'s fate, settled:** it stays the only writer for an `_apsk` no `enroll:request` can carry (a client with no enrollment publishes under `primary`, which has no enrollment record). It now publishes `publicSigningKeyValue` — the **bare** key when the client holds exactly one `rsa2048` key, the array otherwise — which is the same rule `_apskFor` uses for `apsk`-versus-`apskLegacy`; the two must agree because they describe one record. It also **republishes on a change**, closing [decisions.md 91.1](detail/decisions.md#911-what-is-wrong-today) cost 2: it used to read the record, log "have already published" and return, so a rotated key never reached the atServer and every envelope signed with the new one was verified against the old. Proven by mutation: restoring the absent-only condition turns exactly the republish test red. Rails: at_client **1234/1234** (2 skipped), at_auth **269/269** |
| 14 | *(done in step 2a)* `EnrollParams.apsk`/`apskLegacy` are populated at all three submit sites. ⚠️ **This read "Only the atServer half of `apskLegacy` remains" until the 2026-08-14 wrap-up, and that half had merged two days earlier** — at_server `6a86fbcc`, an ancestor of `origin/trunk`, re-verified with `git -C ~/dev/atsign/repos/at_server branch -r --contains 6a86fbcc`. Step 2a was corrected on 2026-08-13 and this row was not, which is how a reader working top-down would have rebuilt merged work |
| 15 | ✅ **DONE 2026-08-13.** `signEnvelope` takes a **list** of keys and emits one signature entry per key, in the order given — which is what the RFC 7515 general serialization the envelope already used is for. `wrapAndSign` passes every key `signingKeys` returns rather than its strongest: the **verifier** chooses, taking the strongest algorithm the envelope and the published `_apsk` share, so signing only under this build's strongest would be unverifiable to any peer that has not implemented it — an envelope carrying both is readable by the upgraded peer and the un-upgraded one, which is the rollout problem in one sentence. The payload is encoded **once** and every entry signs its own protected header joined to that same text, so the entries are alternatives rather than a chain. `SignedEnvelope.fromJson` already refused an empty signatures array and a multi-**signer** document, so the writer builds through it and inherits both refusals. ⚠️ **UC-G1.7's two-signature fixture was hand-assembled** from two single-signature envelopes, so that whole group was a test of the fixture and would have passed against a writer that could not emit two signatures at all; it now drives the real writer. Proven by mutation: signing with `[keys.first]` turns the multi-signature test red. Nothing files per-algorithm signing material yet, so every envelope still carries exactly one signature today, and the stored JWS vector re-signs byte-identically. Rails: at_client **1237/1237** (2 skipped), at_auth **269/269** |
| 16 | ✅ **DONE 2026-08-13, in five commits `e04040ac1`…`d467ed3b5`** — two code, three docs (this row said "in two commits", written before the doc sweep and the wrap-up corrections landed). `AtEnrollment.update` takes an `EnrollmentUpdateRequest` and an `EnrollmentUpdater` sends it, beside `EnrollmentApprover` and deliberately not on it: the approver's verbs need a connection holding `__manage` and act on somebody else's enrollment, while this one needs no privilege and can only act on the enrollment the connection *is* — the atServer refuses an owner connection here rather than waving it through. The request refuses at construction to be built naming nothing to change, with a public key and no private half, with a key and no algorithm or an algorithm and no key, with both `_apsk` shapes, or with an advertisement of no keys. **Found en route: the wire vocabulary was one field short, so this row's "only the caller is owed" was wrong.** `EnrollParams.apkamPublicKeySignature` existed with its own round-trip test, but `EnrollVerbBuilder.buildCommand` never copied it into the params it builds — and a `toJson`/`fromJson` round trip is equally true of a field nothing can send, so the test could not see it. **Two rulings this took:** `signingAlgo` is **always** sent, so the effective algorithm the atServer interpolates is the one signed here and the literal `"null"` can never come from this emitter (pinned regardless — a second implementation has to know the server accepts it); and the public API takes two key-material **strings**, not an `AtPkamKeyPair`, because at_chops deprecates that type and a new signature carrying it hands every caller a deprecation. `ecc_secp256r1` is refused rather than signed: at_chops' pkam-mode signer selects an RSA implementation for everything that is not `mldsa65`, so an ECC key would be signed as though it were RSA — and an ECC APKAM key lives in a secure element whose private half is not a string anyone can pass. **Proven by two mutations**, against tests that re-run the atServer's own `ApkamSignatureVerifier` branches rather than asserting through the signer: signing everything as `rsa2048` turns exactly the mldsa65 arm red (that arm is the only one that can see an algorithm mix-up), and dropping the algorithm from the signable turns all three signature tests red (both arms verify real bytes). ⚠️ **Nothing persists a rotated keypair** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on). Rails: at_commons **517/517**, at_auth **288/288**, at_client **1237/1237** (2 skipped), at_onboarding_cli **39/39**. **THE PoP CONTRACT, read from at_server `6a86fbcc` `enroll_verb_handler.dart` `_verifyApkamPublicKeyPossession` and `apkam_signature_verifier.dart` — do not re-derive it:** signable is `utf8.encode('<enrollmentId>|<apkamPublicKey>|<signingAlgo>')`, signature travels **base64**, signed by the **NEW** private key. Three things a guess gets wrong: (a) `signingAlgo` is the **effective** one, `request.signingAlgo ?? record.signingAlgo`, string-interpolated — so a null becomes the literal `"null"` in the signed bytes, and a client that omits it must know the record's current value; (b) **mldsa65 signs the message DIRECTLY with no hash** (`MlDsa65PureDartAlgo.verifyBytes`), while rsa2048/ecc go through `AtChopsImpl.verify` with `HashingAlgoType.sha256` — a client that hashes for both fails only on the PQ path; (c) `AtSigningMode.pkam`, never `data`, which signs with the *encryption* keypair. The server also refuses `signingAlgo` without `apkamPublicKey`, and `enroll:update` is **self-only** and **approved-only**. ⚠️ **Adding a member to `AtEnrollment` touched 7 `Mock implements` in three packages** (at_auth 2, at_client 4, at_onboarding_cli 1), plus `AtEnrollmentImpl`, which is the **production** class and got a real implementation rather than a stub — not an eighth mock, as an earlier draft of this row said. All three suites re-run; the mocks are safe because no production path calls the new member, and they would have broken at RUNTIME, not analyze |
| 17 | ✅ **DONE 2026-08-13.** `AtClientPreference.inUseSigningAlgorithms` — a `Set<SigningAlgoType>`, final at construction and stored unmodifiable, defaulted from a new fifth `ReleasePosture` axis and overridable per preference. **The four things ruling 16 left open were ruled by gkc and are recorded in [`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 16 with their reasoning:** defaults `{}` in 3.x and `{mldsa65}` in 4.0; a `Set`; final at construction; and an algorithm this build cannot sign an envelope under is refused at construction with an `ArgumentError` rather than skipped. ⚠️ **The doc sweep this owed was bigger than the row** — three documents enumerated the posture's axes and all three still listed the **signed-envelope version**, deleted at step 3: [`decisions.md` 56.4](detail/decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)'s table, its capstone entry [`decisions.md` 70](detail/decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10), and `roadmap.md`'s axis list. The count stayed five across the swap, which is precisely how a stale enumeration survives review. Acceptance gained UC-C1.7 and UC-C1.6's "UC-C1.1–C1.5 prove the arms" was corrected — C1.3 is withdrawn. `design.md` 9.6's strength order still showed the three-member ruling rather than the five-member total order step 7 shipped. **Nothing reads the set yet — step 18 is its only consumer**, so this commit is a preference and its refusal, not a behaviour change. **Proven by four mutations**: each posture default flipped reddens its literal pin, disabling the signable check reddens the refusal test, and returning the caller's own set rather than an unmodifiable copy reddens the containment test. ⚠️ **The 1240/1240 in this commit's message was measured before the doc edits and does not hold for the commit as landed** — adding UC-C1.7 to `acceptance.md` without a scenario in `test/acceptance/` turns `catalogue_test.dart` red, which is that guard doing its job. Fixed in step 18's first commit, which adds the scenario and the README row count. Rails for 17+18a together: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped) |
| 18 | **PART 1 DONE 2026-08-13 — the reader and the advertisement; the minter is part 2.** Splitting it was forced by a defect the minter would have shipped: `ParsedApsk.keyFor` took **one key per algorithm** (`where(alg).firstOrNull`) and `verifyEnvelope` checked that one, so ruling 10's retained authentication key works only where its algorithm differs from the minted key's. A post-quantum-native enrollment's auth key is ML-DSA and so is what it mints, which puts two `mldsa65` entries in `_apsk`, and every envelope signed before the split stops verifying — the ordinary 4.0 case. `keysFor(algo)` is now plural and the verifier tries each, refusing only when none verifies; ruling 10 is amended in place with why. **The reader ships before the writer**, which is also why this is two commits rather than one. Also here: `apskEntries`/`apskValueOf` (`apsk_composition.dart`) are the one composition of the `_apsk` record for both its publishers, and they append the authentication key as `retired` once the enrollment holds signing keys — deduped, because one key described as both current and withdrawn is a document a verifier has nothing to choose on. An enrollment holding no signing material advertises exactly what it did before. ⚠️ **The retention half was reversed 2026-08-14 by row B2** under [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2: the auth key is advertised only while it *is* the signer and is never retained, and what `apskEntries` carries beside the active signers is the enrollment's **retired signing keys**. The dedup survives, between an active signer and a retired entry naming the same public half. **Proven by mutation**: restoring the single-key selection reddens the retained-key test. Rails: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped). ~~**Part 2 owes** the minter itself: mint at start, publish, then file.~~ ✅ **PART 2 DONE 2026-08-13** (`90730a130`, "an enrollment mints its own signing keys, advertising before filing"), and this sentence stayed here reading as owed until 2026-08-18. `SigningKeyMinting` (`signing/signing_key_minting.dart`) mints one keypair per algorithm the in-use set names and the enrollment lacks, retires every held one the set no longer names, and is wired as step 3 of `PqClientBootstrap` (`pq_client_bootstrap.dart:203`); `test/signing_key_minting_test.dart` covers it and `tests/at_functional_test/test/apsk_server_side_test.dart:215` drives it live. The order it owed is the order it shipped in. ⚠️ **That order matters** — filing first makes the client sign with a key its advertisement does not name, and every envelope written in that window is permanently unverifiable, while an advertised key that was never filed costs a verifier nothing and disappears at the next publish. The nskey path's rule is the opposite (`NskeyPrivateFiling.store` files before publishing) because an unopenable *encapsulation* key loses data; the asymmetry is real and worth stating where both are read |
| 18b | ✅ **DONE 2026-08-13.** `SigningKeyMinting` (at_client) mints a keypair for every algorithm the in-use set names and the enrollment does not hold, advertises it, and **then** files it through `WrittenAtKeysIo.update` — the store's atomic verb, because a client's start files conveyed key material through the same keyfile and a hand-rolled read → mutate → write would drop whichever addition flushed first. Wired as the **ninth** `PqClientBootstrap` step, `mintInUseSigningKeys`, gated by `PqStartupGates` and placed **before every step that signs** (seeding, both link publications and the sweep all emit signed envelopes), so a key minted on a start is advertised before anything signs with it. Which writer depends on whether there is an enrollment record: `enroll:update` where there is one — the atServer is the only writer of an enrollment's `_apsk` — and a direct publish under `primary` where there is not. Inert with an empty in-use set (the 3.x default) and inert for a client with no key source, which is the tested no-`AtKeysIo` property. `RsaKeyPair.generate()` rather than `AtChopsUtil.generateAtPkamKeyPair()`, which returns a type at_chops deprecates. **Proven by three mutations**: swapping to file-then-publish reddens the ordering test, dropping the retained authentication key reddens the advertisement tests, and minting an already-held algorithm reddens both idempotence tests. ⚠️ **The second of those mutations no longer discriminates** — row B2 removed the retention it was probing. Its replacement is B2's own pair: gutting `retiredSigningKeysFor` reddens the two retained-signing-key tests, and removing the dedup reddens the third. Rails: at_client **1257/1257** (2 skipped), acceptance **57** (2 skipped) |
| — | *(the original row, kept for its spec pointers)* Mint-on-demand when the in-use set names an algorithm the enrollment lacks. **Spec: ruling 16** (mint locally at start, file it, publish it — a *signing* keypair may, because unlike the auth key it needs no server approval) and **[`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 9** (the array is append-mostly: an algorithm leaving the set stops signing, but its key and its published entry are **retained**, because they are what verify the envelopes it already signed). This is the step that gives `signingKeysFor` something to read — `fileSigningMaterial` has no production writer until it lands |
| 19 | ✅ **DONE 2026-08-13.** The axis is **`SigningRollout`** — `now` / `rollout1` / `rollout2` — on `ReleasePosture.signingRollout`, overridable per `AtClientPreference`, with the in-use signing set **derived** from it rather than stored beside it. **The step opened with a finding that nearly closed it:** the three rollout-2 writer behaviours are inseparable *by construction*, not by three flags agreeing — only minting is a decision, while the array form (`apskValueOf` emits the bare string only for a single active `rsa2048` entry) and the multi-signature envelope (`wrapAndSign` signs with every key the keyfile holds) are consequences of the enrollment holding a second key. Folding the axis away like step 23 was put to gkc and **declined**: the axis earns its place by naming the position, and steps 20–22's driver needs those names. So it names a position and supplies one default, and cannot contradict the behaviour — two stored fields would be two controls over one thing. `rollout1` writes exactly what `now` writes (the reader half needs no gate) and carries the *fleet's* position instead; it is reachable only through the preference, since there are two postures and no general constructor, and an unreachable value would be a rollout position nothing could ever be in. **Proven by three mutations**: giving `rollout1` a non-empty set, ignoring an explicit stage, and letting the stage beat an explicit set each redden their own arm. Rails: at_client **1261/1261** (2 skipped), functional **146/146** at `88ab87b4e` |

⚠️ **The rollout stages were REDEFINED 2026-08-14, and the at-rest keyfile
shape with them. NONE of it is built.** Read
[`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
and [99](detail/decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
for what and why, and **[14.20](detail/implementation-plan.md#1420-building-rulings-98-and-99--the-sequence)
for the order to build them in** — several of those orderings are the difference
between a working rollout and a broken fleet. Read all three before acting on
any row below that names a stage. Rollout 1 now moves the
**authentication** key to ML-DSA-65 and mints a fresh **RSA-2048 signing key**
to advertise in its place: only the atServer verifies the auth key, while every
peer verifies the signing key, so the forgeable-later credential can move first
while the verification surface stays classical. Consequences that touch rows
already marked done:

- ✅ **DONE 2026-08-14 (row B1).** `SigningRollout`'s in-use sets became `{}` /
  `{rsa2048}` / `{mldsa65}`, and it gained
  `defaultRetrofitAuthenticationAlgo`; `retrofitSigningAlgo` is renamed
  `retrofitAuthenticationAlgo` and is now a derived getter (step 17/19's
  landed work, extended).
- `_apskFor` must advertise the **signing** key, not `apkamPublicKey`, and the
  retrofit must mint that key **before** submitting — otherwise a rollout-1
  enrollment publishes an ML-DSA array at creation and breaks every deployed
  reader (step 2a/13's composer, changed).
- `apskEntries` stops appending the authentication key unconditionally;
  [`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 10 is superseded
  and ruling 9 preserved (step 18a's composer, changed).
- **Rollout 1 needs no APKAM rotation**, so it depends on neither step 20's
  rotation arm nor the at_auth release — it is buildable today.

**Stage 4 — the programme pair. This is the validation gate before any PR is carved.**

| # | Work |
|---|------|
| 20 | **MOSTLY DONE 2026-08-14 — the pair runs; the rotation arm is not built.** `tests/pq_matrix/` holds `scenario/`, `current/` and `published/`, three standalone packages. What is built and driven: the stage parameterisation, a real notification, multiple puts and gets with each put read back at the write. **Still owed: enrollment followed by an `enroll:update` APKAM rotation mid-run.** ⚠️ **Its blocker is now an at_auth RELEASE, not a ruling** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) was ruled two-phase on 2026-08-14 and its reader half has landed, so what remains is: publish at_auth carrying the tolerant reader, then add the staged status value, then build the arm. It also needs a dedicated CRAM atSign, since the matrix's demo atSigns hold no enrollment. Do not re-open the persist-before-versus-after question |
| 21 | ✅ **DONE 2026-08-14.** `tests/at_functional_test/test/pq_rollout_matrix_test.dart` runs all sixteen cells, sender and receiver as separate **processes** — they are separate builds, and no one process can hold two versions of at_client. The receiver is spawned first and the sender waits on its `READY` line, because notification streams are broadcast and do not replay. Every cell passes; the failing cells the row used to describe were measured out of existence (see the warning below). **Proven by mutation**: a sender writing `putCount - 1` records reddens the cell, and the error names the missing record, so the receiver genuinely reads from the atServer rather than passing on an empty comparison |
| 22 | ⚠️ **DONE 2026-08-14, then SUPERSEDED the same day.** The row it proves was rewritten by [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 12: rollout 1 publishes a *different key* from `now`, so byte-identity is false by design and the test as landed asserts something that will stop being true the moment the stages are rebuilt. Its replacement asserts the **form** instead, measured by the published arm — a released at_client 3.14.0 reader fetching a rollout-1 sender's `_apsk` and base64-decoding it as an RSA key. **The positive control is the part to keep**: whatever the row asserts, a rollout-2 cell must differ, or it passes for a harness where no stage does anything. *What landed, for the record:* UC-G1.14 runs its own now/now and rollout1/rollout1 cells rather than reading what the matrix loop left behind — a test that depends on another test having run first passes on declaration order, which is not a property of the code. It asserts the published `_apsk` byte-identical and the sender's keyfile byte-identical across the two stages. **It carries its own positive control**, and that is the part worth keeping: a third cell at rollout2 must *differ* on both counts. Without it the row passes just as well for a harness where no stage does anything — which is exactly how a rollout-2 arm attached with no key source reads. Measured: `now` and `rollout1` leave the keyfile at its 5605-byte baseline, `rollout2` leaves 14016 |

Scope of the pair, ruled: the signed-envelope exchange; a real notification and
data path; **multiple puts and gets**; and enrollment followed by an
`enroll:update` APKAM rotation mid-run. The **published** arm runs the last
released at_client and is what makes "`now` is faithful to legacy" a
measurement rather than a claim — see [`acceptance.md` 16.1](acceptance.md#161-the-harness).

**Where it lives, ruled 2026-08-14** ([`decisions.md` 96](detail/decisions.md#96-the-programme-pair-gets-a-home-outside-the-workspace-2026-08-14)):
`tests/pq_matrix/` holding `scenario/`, `current/` and `published/` as three
**standalone** packages — none listed in the root `workspace:`, because
`packages/at_client` is a workspace member and a member cannot depend on the
hosted 3.14.0. `published/` pins `at_client: 3.14.0` exactly with its lockfile
committed; `scenario/` holds the exchange once and each arm supplies only its
own preference construction, so a published-versus-`now` divergence is
attributable to at_client rather than to two hand-written programs. The driver
is a test file in `tests/at_functional_test`, so `runLocal.sh` stays the entry
point.

⚠️ **The matrix is a data-path matrix, and the two failing cells are gone.**
Measured 2026-08-14: at_client 3.14.0 and this tree cannot exchange an envelope
in **either** direction under **any** stage — this tree → 3.14.0 is a
`_TypeError` null cast, 3.14.0 → this tree refuses with "an envelope must carry
its payload as a string". Step 3 deleted the envelope as a posture axis, so no
stage emits the released shape. gkc ruled the break accepted rather than fixed,
on reachability: the released reader is same-atSign only, hangs off an
`@experimental` entry point nothing in 3.14.0 constructs, and that entry point's
dartdoc opens "not yet suitable for production secrets". Both errors are pinned
as raw literals. The rollout-2 cells previously shown as failing with
`IllegalStateException` were wrong on both the cells and the error —
[`acceptance.md` 16.5](acceptance.md#165-the-rollout-matrix) records what it
used to say, and [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rulings 2 and 3 are amended in place.

**Stage 5 — the rest of D1. All in scope; none deferred.**

| # | Work | Entry |
|---|------|-------|
| 23 | *(folded away)* passive-by-default **is** the axis's `now` position | [14.13](detail/implementation-plan.md#1413-a-passive-by-default-flag-surveyed-not-built) |
| 24 | A client with no enrollment id is treated as fully privileged | [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) |
| 25 | A `mintLegacyMaterial:false` atSign cannot write a public record | [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) |
| 26 | *(closed)* revocation visibility — an `EnrollmentManager` cache race, fixed in at_server `16dd457f`. ⚠️ This cell said "a proven test-instrument failure" until 2026-08-15; that was the 2026-08-11 ruling the root-cause overturned | [14.9](detail/implementation-plan.md#149-a-revoked-enrollment-can-still-authenticate-briefly) |
| 27 | ✅ **DONE 2026-08-15** — domain separation on the signed envelope, per-use `typ` plus a root-link prefix ([`decisions.md` 103](detail/decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15)) | [14.8](detail/implementation-plan.md#148-domain-separation-on-the-signed-envelope) |
| 28 | NoPorts' own copy of the envelope shape | [14.7](detail/implementation-plan.md#147-noports-carries-its-own-copy-of-the-envelope-shape) |
| 29 | **Three** audit residuals — perf ceiling on a real low-end device, SS-4 interrupted-mint resume, IS-1 record-name drift. ⚠️ This read **four**, including UC-A3.4's live self-direction, until 2026-08-18 — 14.16's own body has marked that ✅ DONE since 2026-08-17 | [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) |
| 30 | `deprecated_member_use` findings across the workspace (345 at_client, 183 at_onboarding_cli, 110 at_auth, 28 at_lookup) | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) |
| 31 | ✅ **DONE — nothing owed since 2026-08-10.** The one item (the functional pack's compose hardcoding a local image) is struck in the body; the external gate it names is step 32's blocker, not a checklist entry. This row carried no state until 2026-08-18, which in this table reads as open | [14.15](#1415-pre-pr-rails-checklist) |

Also in D1, runnable in parallel: **S-3**'s completion, **B-3** ([#2128](https://github.com/atsign-foundation/at_client_sdk/issues/2128),
open), **KF-1** ([#2129](https://github.com/atsign-foundation/at_client_sdk/issues/2129),
open), and **IS-1**. ~~merging at_lookup 3.6.1 (#2127)~~ — dropped 2026-08-13:
that PR merged 2026-08-08 and 3.6.1 is on pub.dev, so it had been listed as
parallel work for five days after it was finished. Issue states verified with
`gh` on 2026-08-13; re-derive rather than trusting this line.

**Stage 6 — the carve-up, which is where D1 initial development ends.**

| # | Work |
|---|------|
| 32 | Carve the spike into stacked PRs |
| 33 | Merge them to trunk. **The spike branch itself never merges** |
| 34 | ← D1 initial development complete here |

Then, as the release programme rather than development: publish at_chops 3.6.0
→ at_commons **5.16.0** → at_auth 3.4.0 → at_client's GA minor, and finally
**R-2**, the 4.0.0 posture flip. (⚠️ this said at_commons **5.15.0** until
2026-08-13, a version already on pub.dev; the in-tree in-progress heading is
5.16.0. Check pub.dev against every touched pubspec before acting on this
ladder — a same-value version bump merges silently.)


### 14.19 Small items, raised 2026-08-12 and not yet acted on

**10 open, 16 struck** — ⚠️ **re-derive both, never read them here.** This
header said `11 open, 12 struck` until 2026-08-18, and the TODO row three
paragraphs up said 9 the whole time: the count turned out to have **four**
homes, not the two a correction had been updating. (Was 17 open on 2026-08-17,
before items 1, 3, 16, 17 and
19 were fixed, 22 was struck as a false positive, and 15 was struck as the
closure it had already recorded in its own body since 2026-08-15). Each is real
and verified at the time of writing, and each is too small to be a step of its
own. **None blocks anything** — which is why the items themselves live in
[`detail/implementation-plan.md`](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
rather than here: they are work to pick up, not work to hold in mind.

**Item 8 is the only one waiting on a ruling** — typed key material is not
self-encrypted at rest while the flat fields are. Item 10 is an unexplained
functional run with two disproven theories. Item 14 is not PQ at all. Items 20
and 21 were examined and deliberately left, so they are not work.

Re-derive the open count rather than trusting the number above:

```bash
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | grep -cE "^[0-9]+\. \*\*"
```

[14.19.1](#14191-things-that-look-like-defects-and-are-not) stays below,
deliberately: it records proposals that were made and **rejected on evidence**,
and it only works if it is read where the temptation arises.

#### 14.19.1 Things that LOOK like defects and are not

Recorded because each was proposed as a fix and **rejected on evidence**.
Without this note the next reader re-derives the proposal, "fixes" it, and ships
a false claim — one of them was already drafted into a CHANGELOG line before an
adversarial pass killed it. Items 1–3 came from ruling 6; the rest were raised
later, so do not read this list as scoped to one ruling. **Add to it rather
than re-litigating an entry**, and if an entry is genuinely wrong, amend it in
place with what it used to say.

0. **Do NOT add a "refuse a document carrying a top-level `atSignKeys` by
   name" guard.** Proposed 2026-08-15 while renaming that field to
   `atsignKeys`, on the precedent of A1's refusal of a stale top-level `keys`
   (which is a real guard and stays). ⚠️ **The two cases are not alike, and
   the difference is who holds the stale document.** A1's `keys` guard protects
   against a shape *this tree itself wrote and shipped through several of its
   own commits*, so a stale file could plausibly be sitting on a machine that
   matters. `atSignKeys` existed only between A1 and this rename, was never
   released — zero matches across all ten at_auth versions in the pub cache,
   with `class AtKeys` as the positive control — and the only files carrying it
   are ones our own functional runs generate and regenerate. gkc ruled it out
   the same day. A guard here would be code no reachable file can trigger,
   which reads as a supported migration path that does not exist.
1. **A corrupt-base64 pairwise envelope is NOT misclassified as transient.**
   It is tempting to read `sweepOnce`'s broad `catch` arm as the "retry
   forever" path and the `received == null` arm as the "deterministic skip"
   path, and to claim routing the decode through `pqOpenFromBase64` changes the
   outcome. It does not: both arms run the same two statements — release the
   claim, log a warning — and neither deletes, so the envelope waits for ttl
   expiry either way. Only the log line and the classification differ. Do not
   describe this as a behaviour or at-rest change.
2. **An `on PqSealException` arm at the nskey seal site would be dead code.**
   `pqSeal` throws it in exactly one place, the unsupported-version refusal,
   and `NskeyProvider.encrypt`'s own version guard makes that unreachable — the
   version always comes from `sealVersionFor`. The wrong-length-key case that
   arm looks like it catches arrives from `encapsulate`, which at_chops now
   maps itself.
3. **Do NOT tighten `_openIfSymmetricKey`'s `catch (e)` to a typed catch.**
   `enrollment_symmetric_key.dart` documents "every rejection is a skip rather
   than a throw", its caller's poll loop has no `try` at all, and a throw there
   fails the whole enrollment — recoverable only by re-requesting, since the
   conveyed `apkamSymmetricKey` is written once. The breadth is the contract.
   [Section 47.6](detail/decisions.md#476-two-defects-in-the-enrollment-path-both-from-the-same-shape)
   records the two defects that breadth was introduced to fix.
4. **A suite-versus-key-algorithm guard in `_consume` would change no
   outcome.** Once a client can hold keys under more than one KEM
   ([14.18](#1418-the-remaining-d1-initial-development-sequence) step 5), an
   envelope can name an ML-KEM suite and an X-Wing key, and it looks like
   something to refuse before the open. It is not: at_chops maps the
   wrong-length secret key to a `PqOpenException`, which the open already
   catches and skips, and its message names the mismatch outright
   ("ML-KEM-1024 secret key must be 3168 bytes: 32"). The guard was written,
   removing it turned nothing red, and it comes out — a check that changes no
   outcome and reads like a security check it is not. What *does* matter is
   pinned instead: the envelope is skipped rather than crashing the sweep, so
   the good envelopes behind it in the batch still arrive.
5. **Do NOT add `atKeysIo ??= KeychainAtKeysIo()` to at_client_flutter's
   `AuthService.authenticate()`.** `onboard()` has exactly that line
   (`auth_service.dart:40`) and `authenticate()` does not, which reads as an
   oversight and is not. `AtAuthRequest`'s constructor already refuses a
   request carrying neither `atKeysIo` nor `atAuthKeys`
   (`at_auth_requests.dart:119`), so on the authenticate path the `??=` could
   only ever fire when the caller supplied **`atAuthKeys`** — an app that
   loaded its own key material and is telling you so. Defaulting a keychain
   source there points the client at a store that may hold another atSign's
   keys, or none. The asymmetry is correct: onboarding *mints* keys and needs
   somewhere to write them, while authenticating does not. Proposed and
   rejected 2026-08-13 while wiring [14.18](#1418-the-remaining-d1-initial-development-sequence)
   step 11; the same reasoning is now a comment above the method, because the
   invitation is in the file rather than in this document.
6. **Do NOT add `update` to at_client's `EnrollmentService`.** The invitation is
   strong and will recur: `AtEnrollment.update` landed with no at_client-side
   entry point, `EnrollmentServiceImpl` already wraps an `AtEnrollment`, and it
   already forwards `approve`/`deny`/`revoke` — so exposing `update` beside them
   looks like finishing the job. It is not. That facade is the **approver** side:
   every verb on it needs a connection holding `__manage` and acts on *somebody
   else's* enrollment. `enroll:update` is the opposite — no privilege at all, and
   only ever on the enrollment the connection *is*, with the atServer refusing an
   owner connection rather than waving it through. Putting both behind one
   interface makes the two authorities look interchangeable to every caller and
   every reviewer, which is the distinction the whole self-only security argument
   rests on. Note also that the facade does **not** mirror `AtEnrollment` today —
   it carries no `submit`, no `list`, no otp verbs — so "it forwards the others"
   was never the rule. Proposed and rejected 2026-08-13 while landing
   [14.18](#1418-the-remaining-d1-initial-development-sequence) step 16. When
   steps 17–18 need to reach `update` from at_client, give it a seam of its own
   on the signing path rather than widening this one.

7. **Do NOT make the mint lock release itself while its lease is unspent.**
   Proposed 2026-08-16 — by me, and *recommended* — when the first live run of
   [14.24](detail/implementation-plan.md#1424-the-nskey-mint-elects-a-winner--decisions-105) showed a
   rotation refused for the two minutes after a mint. The argument was that it
   is sound by construction: `MintLease.expiresAt` is stamped *before* the take
   goes out, so "unspent by my clock" implies the atServer has not expired it
   either, so the lock cannot be a successor's — closing the stolen-release
   window properly while keeping rotation responsive.
   **gkc rejected it.** Step 6 of the election protocol
   ([decisions 105.2](detail/decisions.md#1052-the-protocol-gkc-specified)) is
   that the winner does not delete the lock, and it binds rotation as well as
   the mint election. The cooldown is the design, not a cost to engineer away.
   ⚠️ **It will look like an obvious improvement again**, because the refusal
   is visible in a test failure and the change is six lines. What is not
   visible from the code is that a lock nobody deletes has **no**
   stolen-release window to close, and adding a delete back reintroduces the
   whole class — which is what
   [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) item 18
   was, and it took two sessions to kill. If this is re-opened, the thing to
   change is the *protocol*, in a ruling — not `MintLock`. See
   [decisions 105.6](detail/decisions.md#1056-built-the-cooldown-binds-rotation-too).

8. **`revokeEnrollmentAndRotate` does NOT retry a rotation the cooldown
   refused, and that was decided rather than overlooked.** It revokes first, so
   a refusal leaves the enrollment cut off from the atServer while still
   holding the live generation. Retrying in-process would mean sleeping for the
   ttl inside a call that already did the destructive half, and swallowing the
   partial state rather than surfacing it. It instead catches per namespace,
   logs `severe` naming the cooldown as the likely cause, and carries on to the
   other namespaces. If this is revisited, the question is whether the CALLER
   can see which namespaces failed — `outcomes` lists only the successes today,
   so a caller counting them cannot tell a refusal from a namespace that had
   nothing to rotate.


### 14.17 Signature agility — complete

✅ **COMPLETE 2026-08-18.** Steps 1–5 are done and step 6 is out of scope by
gkc's ruling. The last piece to land was step 5's signed-envelope 3×3
(UC-G1.15), which is what makes
[`decisions.md` 108](detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
a measurement rather than a ruling.

⚠️ **This entry spent five days claiming steps 4 and 5 were owed after they had
shipped**, because it was written 2026-08-11 and never re-read against the tree
while [14.18](#1418-the-remaining-d1-initial-development-sequence) built the
work. The individual strikes below say what each row used to claim. The reason
nothing caught it is worth more than the corrections: the `UC-G1.x` rows this
entry is accepted against are the one cluster of the catalogue no rail checks —
`manifest.dart`'s regexes hard-code `UC-[ABC]`.

The design landed 2026-08-11 as [`decisions.md` 91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11),
[`design.md` 9](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
and [`acceptance.md` 16](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix).
This entry is the owed half; the rulings are the contract.

**Owed, in dependency order.**

1. ~~**Drop at_server's at_commons override.**~~ **DONE 2026-08-11.** The
   override is out of both `pubspec.yaml` and `pubspec_overrides.yaml`,
   `pubspec.lock` resolves at_commons from hosted 5.14.0, the
   `at_commons-apsk-1` tag is deleted local and origin (its commit `54ccffdd0`
   is an ancestor of trunk, so nothing was orphaned), and
   [at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744)
   **MERGED 2026-08-11** — ⚠️ *this line read "is open for review" until the
   2026-08-14 wrap-up; verified with `gh pr view 2744 --repo
   atsign-foundation/at_server`.* ⚠️ **And the `5bc3618a` this paragraph named
   as at_server's head is long superseded** — it is an ancestor of
   `origin/trunk` now, i.e. landed. ⚠️ **Do not read a SHA here as "at_server's
   head" at all:** `6a86fbcc`, cited elsewhere in this plan for the PoP
   contract, is the tip of the local `gkc-add-apskLegacy-field` branch and is
   *also* an ancestor of trunk; `origin/trunk` itself was at `fdb78568` on
   2026-08-14 and moves independently of anything here. Re-derive with
   `git -C ~/dev/atsign/repos/at_server rev-parse --short origin/trunk`; none
   of this is visible from inside at_client_sdk, which is how both errors
   survived.

   **What this still leaves owed:** at_server's own **210/210** was measured at
   `ab38b884`, several commits back and against a different at_commons source.
   **That number is stale twice over and has to be re-earned before it is cited
   again** — it is at_server's pack, not at_client_sdk's, so none of this
   project's runs discharge it.
2. ~~**Ruling 7's remaining half: flat → typed.**~~ **DONE 2026-08-13**, and
   narrowed on evidence — see [14.18](#1418-the-remaining-d1-initial-development-sequence)
   step 10 and the amendment in [`decisions.md` 91.3](detail/decisions.md#913-the-rulings)
   ruling 7. The projection cannot be **materialised**, so "nothing reads them"
   became "one place reads them": `AtKeys.authenticationFor` /
   `authenticationAlgorithmFor`. ⚠️ **The reader list above was wrong on two of
   its four entries.** `file_io.dart` touches no `AtKeys` flat field at all —
   its only `atKeys.*` uses are `atsign` and `toJson` — and `onboarding_mint.dart`
   *writes* them at mint time, which is the projection working as intended
   rather than a read to move. The two that did move are `AtKeys.toAtChops()`'s
   callers in `at_auth_impl.dart` and, not on the list, `at_client_impl.dart`.
3. ~~**The wire half, client side — none of it exists.**~~ ⚠️ **STOP — this
   whole item is a 2026-08-11 SNAPSHOT and four of its five sub-bullets are now
   FALSE.** Corrected 2026-08-13 after a context-free read of the handoff
   reported that a reader sent here for the step-17 spec would conclude the
   multi-signature writer and the strength order were still owed, and rebuild
   them. **What actually landed** ([14.18](#1418-the-remaining-d1-initial-development-sequence)
   is authoritative, not this list):

   - the `_apsk` **array composer and reader** — steps 6 and 13;
   - the **multi-signature envelope** — step 15. `signEnvelope` takes
     `required List<ApkamSigningKeys> keys` and emits one entry per key;
   - **`requireAlg` no longer exists in any source file** (step 8 replaced the
     refusal with algorithm *resolution*; the only surviving mention is
     `packages/at_client/CHANGELOG.md`). Any line below citing it, or citing
     `envelope_signature.dart:577`, is describing deleted code;
   - the **strength order** — step 7. `SigningAlgoType.strongestFirst` is at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as its tripwire, so
     UC-G1.7 has had something to run against since 2026-08-13;
   - the **`enroll:update` caller** — step 16.

   ⚠️ **The line numbers below are also stale** — `ApkamSigningKeys` is no
   longer at `envelope_signature.dart:197`, and `signingKeys` is at
   `apkam_signing.dart:124` returning `Future<List<ApkamSigningKeys>>`, not at
   `:56`. **Nothing is owed from this item any more** — the in-use signing set
   landed 2026-08-13 as step 17, mint-on-demand as step 18, and row B3 moved
   the mint ahead of the enrollment submission on 2026-08-14. (This line read
   "only mint-on-demand is genuinely still owed" until that sweep.) The original text is kept below
   because its *reasoning* about why each piece is an inversion rather than an
   addition is still worth reading — but read it as history, and verify every
   claim against the source before acting on it.

   - **The `_apsk` array composer and reader.** Today `publishPublicSigningKey`
     (`apkam_signing.dart:38`) `put`s a **single bare key**, and does so only
     when the record is absent — a get-then-put-if-missing. Nothing composes
     `{v:1, keys:[{use, alg, pub, status}]}` and nothing reads it. The
     `use`/`alg`/`pub` vocabulary exists in the tree, but in `key_package.dart`
     (the **KEM** package, a different record) and as `[{alg, pub}]` in
     `pq_signing_root.dart` (the signing root, no `use`, no `status`). ⚠️ ~~**Open
     question when the composer lands:** does `publishPublicSigningKey` retire,
     or does it stay and become a second writer to a record the approval path
     also writes? Its skip-if-present means an enrollment that already published
     a bare string never rewrites it.~~ **ANSWERED by [14.18](#1418-the-remaining-d1-initial-development-sequence)
     step 13 — it stays**, as the only writer for an `_apsk` no `enroll:request`
     can carry (a client with no enrollment publishes under `primary`, which has
     no enrollment record). And the skip-if-present is gone: it **republishes on
     a change**, which was a real defect — a rotated key never reached the
     atServer and every envelope signed with the new one verified against the
     old.
   - **The multi-signature envelope. This is an inversion, not an addition.**
     `signEnvelope` emits exactly one `signature` and one `signingAlgo` from a
     `switch` on a single `SigningAlgoType`, on both the v1 and JWS paths. The
     verifier does not merely lack multi-signature support — it **actively
     refuses** a mismatch, via `requireAlg` at `envelope_signature.dart:577`,
     whose message reads *"the published `_apsk` is a `<algo>` key"*. The
     singular is baked into the behaviour and the diagnostic, so this work
     changes an existing refusal rather than extending a permissive path.
   - ~~**The strength order** beside `SigningAlgoType` in at_chops, with its
     raw-literal tripwire~~ — ✅ **BUILT 2026-08-13** as [14.18 step 7](#1418-the-remaining-d1-initial-development-sequence):
     `SigningAlgoType.strongestFirst` and `strongestOf` at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as the tripwire, and
     [UC-G1.7](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix)
     ("the verifier takes the strongest and does not fall back") reads PROVEN in
     the catalogue. This bullet said "no ordering exists anywhere in at_chops or
     at_client today" for 5 days after it shipped, which left the plan claiming
     an at_chops obligation it did not have.
   - ~~**The `enroll:update` caller** and its PoP signature~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 16](#1418-the-remaining-d1-initial-development-sequence):
     `AtEnrollment.update`, `EnrollmentUpdateRequest`, `EnrollmentUpdater` and
     `apkamPossessionSignature` (`AtSigningMode.pkam`, SHA-256 — ruling 14, and
     `AtSigningMode.data` cannot work). ⚠️ A rotation is not persisted anywhere,
     [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on).
   - ~~**The in-use signing set** on `AtClientPreference`~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 17](#1418-the-remaining-d1-initial-development-sequence):
     `inUseSigningAlgorithms`, defaulted from `ReleasePosture`. The deprecated
     `signingAlgoType` stays where it is — it is the *authentication* key's
     algorithm, a different thing.
   - **Mint-on-demand** when the in-use set names an algorithm the enrollment
     lacks.

   ⚠️ **Neither side of rollout 1 exists yet.** The staging in
   [`design.md` 9](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
   has rollout 1 ship *reader* capability ungated, before any writer emits the
   array — but the client has neither reader nor writer, so the first
   deliverable here is the reader, not the composer, however tempting it is to
   build the thing that produces output you can look at.

   ⚠️ **The writer half is blocked on owed item 2, and the reader half is not.**
   Found 2026-08-11 by reading the source, and it changes the order this entry
   should be worked in:

   - A **reader** needs the published `_apsk` array and the envelope, both
     fetched over the wire. It touches no local key material, so nothing gates
     it. Start here.
   - A **writer** emitting multi-signature envelopes needs one signing keypair
     **per algorithm**, and nothing can supply that today.
     `ApkamSigningKeys` (`envelope_signature.dart:197`) holds exactly one pair
     of `String`s; `signingKeys` (`apkam_signing.dart:56`) reads it out of
     `atChops`, which carries only the APKAM *authentication* keypair; and
     `AtKeys.toAtChopsForEnrollment` (`at_keys.dart:498`) builds that same
     single authentication pair. **Nothing anywhere enumerates an enrollment's
     signing keys per algorithm** — the accessor that would front the array
     does not exist. Sourcing per-algorithm material
     means sourcing from `AtKeys`, and `apkam_signing.dart`'s own dartdoc
     records why that cannot land yet: *"it cannot land until every client has
     an `AtKeysIo` — today it is nullable and most apps supply none, so reading
     through it would break them."* `_atKeysIo` is indeed `AtKeysIo?`
     (`at_client_impl.dart:80`) and honoured only on first construction.
     ⚠️ **Amended 2026-08-13: that quoted dartdoc is now half wrong, and it is
     still in the file.** The claim was measured — 0 of 22 repos on disk
     supplied one — but the cause was one SDK line, and
     [14.18](#1418-the-remaining-d1-initial-development-sequence) step 11 fixed
     it, so an `at_onboarding_cli` client has a source now. What survives is
     that an app building its own client still supplies none *and is entitled
     to*: a source-less client is a deliberate, tested property protecting the
     cicd atServers. So the accessor needs a defined answer for "no source"
     rather than a precondition that there always is one. Rewriting the dartdoc
     is part of step 12.

     ✅ **Resolved 2026-08-13 by step 12.** `AtKeys.signingKeysFor` enumerates
     an enrollment's signing keys per algorithm, and `ApkamSigning.signingKeys`
     is a `Future<List<ApkamSigningKeys>>` sourced from the keyfile. The "no
     source" answer is the APKAM authentication keypair, which is also the
     answer while nothing files signing material — so the accessor is live
     rather than waiting on a writer, and `now`-posture envelopes are
     unchanged. The stale dartdoc is rewritten.

   So **owed item 2 is not merely the largest remaining piece, it is the gate on
   this one** — which is the argument for doing it before the composer, and the
   reason a session that starts with "compose the array" will not finish it.
4. ~~**The rollout axis.**~~ **DONE 2026-08-13** as
   [14.18](#1418-the-remaining-d1-initial-development-sequence) step 19, and
   built out further by rows B1 and B3 on 2026-08-14. ⚠️ **This item read "the
   axis has no name yet" until 2026-08-18, and had been false for five days.**
   The axis is `SigningRollout` — `now` / `rollout1` / `rollout2` — on
   `ReleasePosture.signingRollout` (`release_posture.dart:154`), overridable at
   `AtClientPreference.signingRollout` (`at_client_preference.dart:104`), and
   read in production by `self_retrofit.dart:117`, `signing_key_minting.dart`
   and the `_apsk` composer. Its premise was wrong as well as its status:
   the stage does **not** switch three flags. Only minting is a decision; the
   array form and the second signature are consequences of how many keys the
   keyfile holds, and the stage supplies one default,
   `AtClientPreference.inUseSigningAlgorithms`.
   [`design.md` 9.7](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
   has said so since it was written, which is where this row should have been
   checked against.
5. **The rollout harness — the data path is built; the envelope grid is owed.**
   ⚠️ **This item read as wholly owed, and named a 3×3, until 2026-08-18.**
   Built as [14.18](#1418-the-remaining-d1-initial-development-sequence) steps
   20–22: the two stage-parameterised executables are `tests/pq_matrix/`
   (`scenario/`, `current/`, `published/`), driven by
   `tests/at_functional_test/test/pq_rollout_matrix_test.dart` as a **4×4**
   matrix over `published`/`now`/`rollout1`/`rollout2`. All sixteen cells pass,
   and the "failing cell asserted by its specific error" this row asks for no
   longer exists — both cells were measured out of existence on 2026-08-14 and
   [`acceptance.md` 16.5](acceptance.md#165-the-rollout-matrix) records what it
   used to say.

   ✅ **The signed-envelope grid closed it the same day.** It was the one piece
   of this row genuinely owed — the 4×4 does not touch the envelope path at all
   (`git grep 'wrapAndSign\|signEnvelope\|verifyEnvelope' -- tests/pq_matrix`
   returned nothing, against `EnvelopeSigning` as a positive control), so the
   sixteen green cells were not evidence about envelope verification. Built as
   UC-G1.15: nine cells over `now`/`rollout1`/`rollout2`, each signing at the
   sender's stage and verifying at the receiver's through a real `_apsk` fetch.
   It is a 3×3 rather than a fourth row and column because a released client and
   this tree cannot exchange an envelope in either direction under any stage.

   **`rollout2 → rollout1` passes**, which is what turns
   [`decisions.md` 108](detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
   from a ruling into a measurement: strongest signer, weakest verifier, and no
   overlap needed because verification is ungated.

   ⚠️ **The nine cells are not what proves the stages differ, and this is
   measured rather than argued.** Mutating `rollout2` to resolve as `rollout1`
   leaves **all nine passing** — a sender signing RSA-2048 verifies everywhere
   too. What catches it is the algorithm assertion: `rollout2 → rollout2` must
   be exactly `['ML-DSA-65']`, `now → now` must not contain it. Both arms in one
   session: the mutation reddens naming `['RS256']`, the revert is green.
   The envelope half lives in `current/lib/envelope_exchange.dart`, not the
   shared scenario, because 3.14.0's `wrapAndSign` returns a `Map` where this
   tree's returns a `SignedEnvelope` and 3.14.0 ships no `lib/src/signing/` —
   a shared file would not compile on the published arm.
6. ~~**`enroll:update` parity for every other atServer implementation.**~~
   ⛔ **OUT OF SCOPE — gkc, 2026-08-18.** Do not re-raise it, and do not file a
   tracking issue for it. Recorded here rather than deleted because it was
   raised three times in one session, each time from re-reading this row as
   owed.

⚠️ **"Still owed: an `mldsa65` arm on the rotation tests" was struck 2026-08-18.**
The sentence dated from 2026-08-11 and the arm has since been written:
`packages/at_auth/test/enrollment_update_test.dart` carries both algorithms (15
`rsa2048` mentions, 10 `mldsa65`), and `signing_key_minting_test.dart` covers
the mint-and-retire path under `mldsa65`. The reasoning it recorded is still
right — picking `rsa2048` for a fixture is the choice that makes a wrong answer
invisible — which is why it is struck here rather than deleted.

### 14.15 Pre-PR rails checklist

✅ **NOTHING OWED, since 2026-08-10.** The single item is struck below. What
remains is the external gate — the published atServer image verifying ML-DSA
PKAM — and that is **step 32's blocker**, not a checklist entry. ⚠️ This section
sat in the TODO table until 2026-08-18 because its opening read as a condition
rather than a status, which also put the done marker outside the window the new
TODO-row guard reads.

No PR opens against this branch until the published atServer image verifies
ML-DSA PKAM (owner's call, 2026-08-08). The one thing that had to be true by
then:

> ~~The functional pack's compose hardcodes a local image, so CI's
> `docker compose pull` kills the job~~ — **done, verified 2026-08-10.** All
> three packs now commit `image: ${VIRTUALENV_IMAGE:-atsigncompany/virtualenv:vip}`
> (functional `docker-compose.yaml:13`, e2e `:14`), and each `runLocal.sh`
> exports `VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"` and
> skips `docker compose pull` for a name containing no `/`. A clean checkout
> and CI therefore resolve the published image with no environment set, while
> our runs opt into the local build. **Nothing needs reverting before a PR.**

1. **The `pqe2e_tests` CI job is written but UNVERIFIED.** Nothing has run it
   end to end, because no published image supports the tests it runs. Run it
   once the image lands, before trusting it. An image without PQ support fails
   at authentication with a server-side
   `AT0010-Exception: RangeError (length): Invalid value: Not in inclusive range 0..47: 48`
   from `AtLookupImpl.pkamAuthenticate` — that signature means the image, not
   the client.


### 14.14 A client with no enrollment id is treated as fully privileged

`EnrollmentRecordPrivilegeResolver.isFullyPrivileged()`
(`service/enrollment_privilege_resolver.dart`) returns **true unconditionally
when `enrollmentId == null`**, ⚠️ **and its own dartdoc now argues the case this
item still frames as an open question** — *"a client with no enrollment id is
authenticating with the atSign's own keys, which is full privilege by
construction rather than by grant."* The behaviour is unchanged. This item cited
`AtClientImpl._resolveFullPrivilege()` until 2026-08-18, a name that had been
moved verbatim on 2026-08-10 (`289bbe453`) and exists in no source file —
`git grep` finds it only in these docs. Also, and `ApkamSigning.enrollmentId` substitutes the
sentinel `'primary'` when there is none. So a legacy PKAM client that happens to
hold an `AtKeysIo` publishes `public:_apsk.primary.a.__e@<atSign>` and signs
approval-chain links as `"primary"`.

Found while surveying for [14.13](detail/implementation-plan.md#1413-a-passive-by-default-flag-surveyed-not-built),
and worth separating from it: a flag would *hide* this rather than resolve it.
The question is whether an owner-keys client should be in the enrollment trust
chain at all, and if so under what identity — `'primary'` is a name no
enrollment record carries.


### 14.12 A `mintLegacyMaterial:false` atSign cannot write a public record

Found 2026-08-08 by UC-B4.2's opt-out arm, the first thing ever to activate an
atSign that way and then use it. The opt-out works exactly as designed at
activation — no RSA keypair is minted, no `public:publickey` is published, and
`completeActivation` says so — but the resulting atSign cannot then publish
anything, because **every public write is signed with the legacy encryption
private key**
(`put_request_transformer.dart` `_signPublicData` throws
`AtPrivateKeyNotFoundException('Failed to sign the public data')` when it is
absent). Two things the post-quantum path itself needs are public writes: the
enrollment's `_apsk` anchor to the signing root, and the nskey advertisement.
Both fail, live and logged, on an opt-out atSign. Sync fails alongside them —
"Self encryption key is not set for current atSign" — because there is no
`selfEncryptionKey` either.

So `mintLegacyMaterial: false` is a switch that exists and is honoured but is
**not yet a usable configuration**, which matters because
[decisions 42](detail/decisions.md#42-the-to-define-list-ruled-2026-08-05) item 10 has
the release default resolving null→false in the major after R-2. Closing it means public-record signing moves onto the
ML-DSA signing root rather than the RSA encryption keypair — the same swap
IS-1 made for inter-server auth — and self data moves off `selfEncryptionKey`
onto the nskey path (B-3 phase 1). Neither is scheduled here; the point of this
entry is that the stop-release cannot ship before both are, and that the
`mintLegacyMaterial` flag must not be recommended to anyone until then.

Asserted, rather than merely noted, in the opt-out arm of
`tests/at_functional_test/test/pq_legacy_interop_live_test.dart`: it expects the
public write to fail with that exact reason, so whichever project fixes this
gets a red test naming the row that was waiting for it.


### 14.11 `deprecated_member_use` findings across the workspace

Everything else `dart analyze` reported is cleared (`3e3ac1075`); at_chops and
at_commons are clean outright. What remains is live use of
deprecated-but-still-required APIs — the `AtChops` compatibility shim,
`AtSigningInput`, `apkamPublicKey` — so clearing them means migrating call
sites, which is a code change rather than a lint sweep and wants its own pass.

**Re-measured 2026-08-18** (⚠️ **re-run it rather than quoting the table** —
`at_client` read 340 here from 2026-08-13 until this measurement, and the
heading said 299 and named only at_client before that). Per package,
`dart analyze lib test` from each package directory, exit code printed
separately, counted with `grep -c deprecated_member_use`. Every package exited
0, and only `at_client` moved:

| package | findings |
|---|---|
| `at_client` | 345 |
| `at_onboarding_cli` | 183 |
| `at_auth` | 110 |
| `at_lookup` | 28 |
| `at_chops`, `at_commons` | 0 |

⚠️ **Scope this before starting it — a straight "migrate off the deprecated
member" sweep is not available for the PKAM signing path.** `PkamSigningAlgo`
and `PkamMlDsa65SigningAlgo` are both deprecated *classes*, and so are
`AtChopsImpl`, `AtChopsKeys`, `AtSigningInput`, `AtSigningMode` and
`AtPkamKeyPair`. Non-deprecated key material *does* exist —
`RsaSignatureAlgo`, and `MlDsa65PureDartAlgo.signBytesSync`/`verifyBytes` with
explicit keys — so what is missing is not a replacement but the **dispatcher**:
nothing non-deprecated selects an algorithm from a `SigningAlgoType` the way
`AtChopsImpl.sign` does in pkam mode. A caller wanting both algorithms writes
the two-way branch itself.

And the RSA arm is not a free swap: the atServer's `ApkamSignatureVerifier`
records that **`RsaSignatureAlgo` refuses any modulus that is not exactly 2048
bits, which `PkamSigningAlgo` does not**, so adopting it would stop an
enrollment holding an off-size RSA key from authenticating. That is a change to
what verifies on the authentication path, not a refactor. Any sweep that
touches signing has to decide this deliberately; the rest of the findings
(models, `apkamPublicKey`, collection APIs) are ordinary migrations.


### After D1

The release programme is **not** part of D1 initial development, and it ends
with **R-2**, the 4.0.0 posture flip (a pure default-flip: 4.0 is identical to
final-3.x *code*).

**The ordered publish list lives in one place:**
[detail/implementation-plan.md — what still has to be published, in order](detail/implementation-plan.md#what-still-has-to-be-published-in-order).
It is not restated here. This block used to carry its own copy, as did
[#1889](https://github.com/atsign-foundation/at_client_sdk/issues/1889), and
all three drifted: two of them were still naming an at_commons slot 3 releases
behind.

✅ **The first rung is settled: at_chops publishes as 3.6.0, a minor**
([decisions 109](detail/decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18),
gkc 2026-08-18). This reverses the in-principle position of 2026-08-13, and the
4.0.0 bump built and reverted that day is not to be re-attempted. 3.6.0 does
carry two source-breaking changes, and the judgement is that no consumer exists
for either to break: trunk's at_client compiles and tests green against this
branch's at_chops, and every `AtKemAlgorithm` implementer sits inside at_chops.
So the 6 workspace constraints do **not** have to widen together, and at_lookup
does **not** need 3.6.2 opened.

## PARKED

Set aside deliberately. A row here exists to stop someone building it, so
the reason is the point of the row.

| Item  | What it is                                           | Why it is parked |
|-------|------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| 14.26 | A false comment in at_server's `at_metadata_builder` | ⛔ **NOT PART OF D1** (gkc, 2026-08-16). It lands in at_server, off `trunk`, and nothing in D1 waits on it. Detail: [14.26](detail/implementation-plan.md#1426-a-comment-in-at_server-is-now-false) |
| 14.1  | The signing root's `keys[]` shape                    | SUPERSEDED by decisions 101 and 14.22. Kept for the reasoning; two of its conclusions are now false |
| 14.13 | A passive-by-default flag                            | FOLDED AWAY 2026-08-11 into the rollout axis (14.18 step 19). Kept for its survey |
| 14.21 | The signing root cannot be rotated                   | RULED the same day by decisions 101. Kept so 14.22 is legible against it |
| 14.23 | Per-generation nskey records                         | ⛔ REJECTED — do NOT build. 14.24 shipped instead; the body is kept so it is not re-derived |
| KE-2  | The `enroll:update` **writer**                       | Verb merged to at_server `trunk`; the client receiver answers at every held kpid. Owed: nothing mints a second KEM key and re-advertises, so a package cannot gain one — which is what blocks the two skipped acceptance rows. Issue #2133 |
| B-3   | Stop **conveying** the legacy `selfEncryptionKey`    | Narrower than it reads: the key's *use* is retired by the release cadence (R-2 flips `disallowLegacyEncryption`), so this is only relaxing `enroll:approve` to accept an approval that omits `encryptedDefaultSelfEncryptionKey` — every atServer implementation, one sweep — then ceasing to mint and convey it. Ecosystem-gated by decisions 37. Issue #2128 |
| KF-1  | `.atKeys`-at-rest protection + backup/restore        | Off the GA critical path. Issue #2129 |
| S-5   | at_auth 4.0.0 WASM barrel split                      | Off the GA critical path |
| S-6   | Consumer constraint bumps onto at_auth ^4.0.0        | Follows S-5 |
| R-2   | at_client 4.0.0 posture defaults                     | After D1. A pure default-flip: 4.0 is identical to final-3.x code |
| D2-1  | Carve `at/pqmls` + D1-E shape fixes                  | D2, out of D1 |

---

## DONE

One row each; the detail is in
[`detail/implementation-plan.md`](detail/implementation-plan.md). The third
column reports what the plan **records**, which is not always what was
measured — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none).

⚠️ **So not every row here says "done", and the heading names this section's
place in the TODO / DONE / PARKED triad rather than every row's state.** Six
project rows record *no status* or a partial one and point at 14.25; **IS-1
records an OPEN PR** (`at_server#2683`, verified against GitHub 2026-08-18).
That is deliberate and the column header says so — but do not read a row's
presence here as delivery. What is actually left for D1 is
[14.18](#1418-the-remaining-d1-initial-development-sequence)'s steps, not the
absence of a row from this table.

| Item   | What it delivered                                       | State as the plan records it                                                                                         |
|--------|---------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| 14.15  | Pre-PR rails checklist                                  | DONE 2026-08-10 — the compose-image item is struck in the body and nothing needs reverting before a PR. It stayed in TODO until 2026-08-18 because the section opened with a condition instead of a status. The external gate it names is step 32's blocker |
| 14.17  | Signature agility, and the G1 cluster joins the catalogue | DONE 2026-08-18 — steps 1–5 done, step 6 out of scope by gkc's ruling; the last piece was the signed-envelope 3×3. ⚠️ **This row sat in TODO reading "the owed half" for the rest of that day**, while the section's own body said COMPLETE — the shape the plan's own re-derivation warning names, where a body says closed and the heading nothing keys on says open. A cold read caught it. The section heading moved with this row. Body: [14.17](#1417-signature-agility--complete) |
| 14.36  | `send()` composes its command with `NotifyVerbBuilder`, and finally has live coverage | DONE 2026-08-17 — the hand-rolled `notify:` string is gone; `useAtKeyToString = true` is required, since the name is split across `key` and `namespace`. One wire delta, `:notifier:SYSTEM`. **`send()` had no live test at all before this**, so the wire delta was landed with one added rather than on the inference that `notify()` already sends the token. The architecture guard moved with it: requiring `toAtProtocolFragment` in this file would now force the hand-rolled command back, so it asserts the absence of one instead. Body: [14.36](#1436-sends-command-is-hand-rolled-where-a-tested-builder-exists) |
| 14.35  | `send()` splits its name at the first dot, and says what the parameter is | DONE 2026-08-17 — gkc ruled the parameter is `<id>.<namespace>` and poorly named; `namespace` deprecated for `idAndNamespace`, a dot-free name now throws at the call site. Unit **1401 (2)**, analyze exit 0. The one-line fix this row first proposed was measured WRONG — it would have changed the ciphertext binding. Body: [14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given) |
| 14.33  | Closed as mis-stated: the refusal it named is unreachable | CLOSED 2026-08-17 — `shared_key.*` is written by a raw `UpdateVerbBuilder` at a `Secondary`, downstream of a refusal that fires before `provider.encrypt`, so it can never reach it. No client-side blocker remains for R-2. The real gap it was standing in front of is [14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given). Ruling [107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17) amended in place. Detail: [14.33](detail/implementation-plan.md#1433-closed-the-shared_key-refusal-was-never-reachable) |
| 14.30  | A notification that outruns its key is parked and re-driven | DONE 2026-08-17 — ruling [106.5](detail/decisions.md#1065-ruled-park-and-re-drive-not-readiness-at-the-hand-back-2026-08-17); proven live end to end (parked → asked → answered → filed → re-driven → decrypted). Three further defects fixed on the way, all invisible to unit tests. Body: [14.30](#1430-a-content-notification-can-outrun-the-key-that-opens-it) |
| 14.32  | An in-process `_apsk` write no longer clobbers a just-minted advertisement | DONE 2026-08-17 — ruling [102.2](detail/decisions.md#1022-the-in-process-window-is-closed-by-serialising-the-writers-2026-08-17); proven live, `_apsk.primary` ends on the mldsa65 array where it ended on bare RSA. Body: [14.32](#1432-a-primary-clients-ml-dsa-signing-key-is-not-visible-to-its-verifiers) |
| 14.31  | A `local:` record is not encrypted, and the legacy refusal exempts it | DONE 2026-08-17 — six related defects, not one; the listener no longer dies from a refused watermark. Ruling [107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17). Body: [14.31](#1431-a-refused-watermark-write-permanently-disables-the-monitor) |
| 14.25  | Nine project entries reconciled against the tree | DONE 2026-08-16 — burn-down right about 4, headings stale for SS-1c and SS-4, real residuals in SS-2/B-1/S-3 (now [14.29](#1429-the-residuals-1425-surfaced)). ⚠️ Re-read 2026-08-18: **B-1's are gone** and S-3 is down to two, so what this row surfaced was two-thirds transient. Detail: [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none) |
| 14.28  | Live PQ proofs that no use case names | DONE 2026-08-16 — 9 uncited PQ live files ruled on: 5 became UC-B5.8–B5.12, 4 were already covered. Detail: [14.28](detail/implementation-plan.md#1428-live-pq-proofs-that-no-use-case-names) |
| 14.27  | The ledger's append-only rot, corrected | DONE 2026-08-16 — 11 rulings amended in the body and LIVE in the index, both citation debts discharged, and a test now asserts each. Detail: [14.27](detail/implementation-plan.md#1427-the-ledgers-remaining-append-only-rot) |
| 14.24  | The nskey mint elects a winner; the lock became an election token with a cooldown | DONE 2026-08-16 — seven rows, proven live at functional **166/166 `EXIT=0`**. Detail: [14.24](detail/implementation-plan.md#1424-the-nskey-mint-elects-a-winner--decisions-105) |
| P-1    | at_chops stateless core + HPKE                          | SATISFIED — at_chops 3.3.0 published 2026-06-23                                                                      |
| P-2    | `mldsa65` wired into the verification branch            | SATISFIED — published 2026-07-17                                                                                     |
| P-3    | `public:pqpublickey` + X-Wing-preferred enrollment wrap | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| S-1    | at_auth `AtKeys`/`AtKeysIo` extended in place           | SATISFIED — at_auth 3.3.0 published                                                                                  |
| S-2    | `CryptoContext.keys` additive field                     | SATISFIED on trunk 2026-07-17; residual is the at_client publish                                                     |
| S-3    | Updatable `.atKeys` / keychain via injected `AtKeysIo`  | States PARTLY LANDED — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                 |
| SS-0   | WP-SS substrate baseline                                | SATISFIED — merged 2026-07-17                                                                                        |
| SS-1a  | at_commons enroll grammar + flattened `listns`          | SATISFIED — at_commons 5.12.0 published 2026-07-04                                                                   |
| SS-1b  | atServer stores/returns `EnrollParams.metadata`         | SATISFIED — merged 2026-07-07                                                                                        |
| SS-1c  | Client wired to the live verbs + flattened parser       | States live drive owed — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)               |
| SS-2   | Substrate wired into AtClient + server wake-up          | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| SS-3   | Substrate hardening + `signingAlgo` verify              | LANDED — at_server#2739 merged 2026-08-10                                                                            |
| SS-4   | nskey minting + signing-root lifecycle                  | States ABOUT HALF LANDED — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)             |
| B-1    | The nskey data path — providers + cold start            | No status stated; the D1 centrepiece — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none) |
| RF-1   | `requestSecret(name)` confirm                           | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| RF-SRV | atServer authenticated self-retrofit enroll             | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| RF-2b  | PQ ML-DSA APKAM mint + self-retrofit                    | LANDED 2026-08-05 (decisions 43)                                                                                     |
| RF-2c  | Retrofit orchestration + full e2e                       | LANDED 2026-08-05 (decisions 44)                                                                                     |
| R-1    | `disallowLegacyEncryption`                              | DELIVERED 2026-08-05; scope shrunk by decisions 36                                                                   |
| SH-1   | Key-material self-heal                                  | LANDED 2026-08-05                                                                                                    |
| B-2    | nskey rotation + revocation                             | LANDED 2026-08-06                                                                                                    |
| KE-1   | Selectable KEM + negotiated construction                | LANDED 2026-08-07                                                                                                    |
| ON-1   | PQ-native greenfield onboarding + opt-out               | ACCEPTANCE COMPLETE 2026-08-08 (decisions 52)                                                                        |
| IS-1   | Inter-server FROM/POL signature swap RSA → ML-DSA-65    | ⏳ **PR [#2683](https://github.com/atsign-foundation/at_server/pull/2683) is OPEN** — verified against GitHub 2026-08-18, not merged. This cell said only `PR #2683`, which reads as delivery and asserted no state at all |
| 14.2   | A version on the two signed payloads                    | DONE — `3c2eddbe6`                                                                                                   |
| 14.3   | JWS for the signed envelope, one shape, no flag         | DONE 2026-08-09 (decisions 60)                                                                                       |
| 14.4   | A `suites` list on the key package                      | DONE — `1688ed69d`, corrected `c9f8580da`                                                                            |
| 14.5   | Write-side envelope version selector in at_chops        | DONE — `1688ed69d`                                                                                                   |
| 14.6   | `metadata.keyPackage` stops being a one-way door        | DONE 2026-08-13 — the verb reaches `metadata` and `EnrollmentUpdateRequest.metadata` merges per-key, so the remedy for an unparseable key package is no longer delete-and-re-enrol. ⚠️ A **consumer** is still owed — nothing re-advertises a key package — and that is **KE-2**'s scope in PARKED, not this row's. This cell said only "Client caller landed" until 2026-08-18, which asserted no status at all |
| 14.8   | Domain separation on the signed envelope                | DONE 2026-08-15 (decisions 103)                                                                                      |
| 14.9   | A revoked enrollment could still authenticate           | ROOT-CAUSED 2026-08-12; fixed in at_server `16dd457f`                                                                |
| 14.10  | UC-B0.1 needed a legacy atServer image                  | RESOLVED 2026-08-08 via the `vip-p3.15.0` pin                                                                        |
| 14.20  | Building rulings 98 and 99                              | DONE — every row built; owes nothing                                                                                 |
| 14.22  | Making the signing root rotatable                       | DONE 2026-08-15 — all seven rows                                                                                     |

---

## Re-deriving the state


Run these rather than trusting the table. Each answers one row.

```bash
# row 1: which 14.22 rows have landed? Row 1 landed when this file started
# composing apskAdvertisement; row 2 is unbuilt for as long as the prefix
# still names one algorithm.
git grep -n "keyIdPrefix =\|apskAdvertisement" -- packages/at_client/lib/src/crypto/nskey/

# row 11: which 14.19 items are still open? (~~struck~~ ones are done)
# ⚠️ Against detail/, NOT this file. The items moved there in the restructure
# and this copy was left pointing here, where it matches nothing: it printed
# ZERO and exited 1 while the answer was 17, so a reader working down this
# block concluded there was no open work. Fixed 2026-08-16.
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | grep -cE "^[0-9]+\. \*\*"     # RUN IT. A number written here is a fifth home
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | grep -cE "^[0-9]+\. ~~"       # likewise. Both said 11/12 on 2026-08-18 against an actual 9/16

# rows 3-9: the stage-5 table, which owns steps 23-31
awk '/^\*\*Stage 5/,/^\*\*Stage 6/' docs/projects/pq/implementation-plan.md

# acceptance: what is skipped, and on which blocker.
# Anchor on "}, skip:" — a bare "skip:" also matches catalogue_test.dart's and
# manifest.dart's prose ABOUT skips and reports 5 where the answer is 2.
grep -rn "}, skip:" packages/at_client/test/acceptance/*_test.dart
grep -n "blocked:\|owed:" packages/at_client/test/acceptance/blockers.dart

# row 2 and row 12: the external gates. The at_auth release is a pub.dev
# question; the atServer image gate is gkc's call and is NOT to be checked
# against atsigncompany/virtualenv:vip (ruled 2026-08-13).

# rails, all four packages. EACH FIGURE CARRIES THE COMMIT IT WAS MEASURED AT —
# a block with one date at the bottom invites reading every number as current,
# and three of these five were re-measured 15 commits after the other two.
cd packages/at_client         && dart analyze lib test       # exit 0, 351 info  @9debd5a01+14.24
cd packages/at_client         && dart test --concurrency=1   # 1350 (2 skipped)  @9debd5a01+14.24
cd packages/at_client         && dart test test/acceptance --concurrency=1  # 66 (2)  @9debd5a01+14.24
cd packages/at_auth           && dart test --concurrency=1   # 312              @7c6b3e7f2
cd packages/at_onboarding_cli && dart test --concurrency=1   # 39               @7c6b3e7f2
cd tests/at_functional_test   && bash runLocal.sh            # 166/166 EXIT=0   @9debd5a01+14.24
# ✅ The functional figure is now measured against the REBUILT
# `at_virtual_env:local` (2026-08-16), which the previous 165/165 was not — that
# one predated the rebuild and was never a claim about the image on this
# machine. 166 is 165 plus the cooldown row 14.24 added.
# ⚠️ at_auth and at_onboarding_cli were NOT re-measured here and still carry
# @7c6b3e7f2. Do not read the block as one date.
# Every figure in this project has been wrong at least once by being carried
# forward — the COMMAND is the value here, not the number beside it.
```


### After D1

The release programme is **not** part of D1 initial development, and it ends
with **R-2**, the 4.0.0 posture flip (a pure default-flip: 4.0 is identical to
final-3.x *code*).

**The ordered publish list lives in one place:**
[detail/implementation-plan.md — what still has to be published, in order](detail/implementation-plan.md#what-still-has-to-be-published-in-order).
It is not restated here. This block used to carry its own copy, as did
[#1889](https://github.com/atsign-foundation/at_client_sdk/issues/1889), and
all three drifted: two of them were still naming an at_commons slot 3 releases
behind.

✅ **The first rung is settled: at_chops publishes as 3.6.0, a minor**
([decisions 109](detail/decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18),
gkc 2026-08-18). This reverses the in-principle position of 2026-08-13, and the
4.0.0 bump built and reverted that day is not to be re-attempted. 3.6.0 does
carry two source-breaking changes, and the judgement is that no consumer exists
for either to break: trunk's at_client compiles and tests green against this
branch's at_chops, and every `AtKemAlgorithm` implementer sits inside at_chops.
So the 6 workspace constraints do **not** have to widen together, and at_lookup
does **not** need 3.6.2 opened.
