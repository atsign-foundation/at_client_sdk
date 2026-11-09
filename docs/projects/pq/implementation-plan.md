# implementation-plan.md — what is still owed

⛔ **This document records only what is still owed** (gkc, 2026-08-23). What has
been done is in the codebase and in `git log`; a rejected proposal or a
measurement that closed a question lives in [`decisions.md`](decisions.md),
because no commit can contain a thing that was never built.

**There is ONE PQ list, and it is [`## TODO`](#todo) below.** Every open item has
a priority and appears exactly once, as one or two sentences: the task, and the
reason where it is not obvious. Detail for an open item is a `###` section under
the list or a ruling in `detail/decisions.md`.

**Item ids are permanent.** An item keeps its `14.x` id wherever it sits, because
the ids are cited from the ledger and the sibling docs; nothing here is ever
renumbered.

**The priorities** (gkc, 2026-11-07, renaming the 2026-08-26 bands once the
first phase shipped):

| | |
| --- | --- |
| **P0** | do next — including work blocked elsewhere; the `Blocked on` column carries startability |
| **P1** | must do |
| **P2** | should do if there is time |
| **P3** | nice to have, or in another repo |

⚠️ **Re-derive before acting on any row.** Every figure in this project has been
wrong at least once by being carried forward; the commands are in
[Re-deriving the state](#re-deriving-the-state).

"All acceptance tests pass" is true today and is not yet that. The rail checks
structure — a scenario exists, ids resolve, counts match, and where a citation
pins THEN clauses each pin resolves to exactly one — while whether a cited test
really *establishes* its clause is the citation's own `proves:` judgement. The
clause meter is the measure; re-derive it, never quote it.

⛔ **From at_client 4.0.0 the post-quantum formats are a compatibility
promise.** The PQ files no longer carry `@experimental` (gkc, 2026-10-29), and
at_client 4.0.0 shipped on 2026-11-04 writing post-quantum key material, so a
change to a persisted or wire format those files define needs a compatibility
path. This replaces the standing premise that no production `.atKeys` file held
PQ key material: that premise ended with the release, and a question closed on
it is re-asked rather than re-cited.

**Other live projects keep their own lists** and are not in the table below:
[`docs/projects/wasm/`](../wasm/implementation-plan.md) (with the client storage
X series), [`docs/projects/bdd/`](../bdd/roadmap.md),
[`docs/projects/deprecations/`](../deprecations/plan.md), section 6 of
[`docs/projects/at-lookup-consolidation/plan.md`](../at-lookup-consolidation/plan.md),
and the knowledge base ([`docs/knowledge/README.md`](../../knowledge/README.md)).

---

## TODO

⛔ **The single list. One row per open item, bucketed by priority; a row says
what is owed in one or two sentences and links to a `###` section or a ruling
where more is needed.**

**The next move is: pick a P0; if none, a P1, and so on** (gkc, 2026-08-26). A
row whose `Blocked on` column says anything but Nothing is not pickable. Nothing
ranks within a bucket, there is no `[RECOMMENDED]` marker and no "next move"
section, and when more than one row in the highest non-empty bucket is
pickable, **ask gkc which** (his ruling, 2026-08-27).

**A row leaves this table when it is done — it does not gain a ✅.** What was
done is in `git log`; a row that is finished and still here is a defect, and a
rail enforces the direction (`docs_structure_test.dart`, *no TODO row names a
section whose body declares itself done*). `## PARKED` holds what was set aside
on purpose, with the reason.

### P0 — do next

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **the acceptance catalogue's default-flip passes** | When each default flip lands — `legacy` to `pqReady` in a 4.x release after 4.0.0, `pqReady` to `pqActive` at 5.0 — the same commit edits every `acceptance.md` clause that names a posture, so the catalogue describes the tree it ships with — never before, and found from the flip's own diff rather than from a list here. | the 4.x default flip: `AtClientPreference` still defaults `posture` to `PqPosture.legacy` |
| **the clause burn-down: live proof** | Every clause proven only in-process gains a proof against a real atServer where feasible; `liveProofOwed` in `packages/at_client/test/acceptance/manifest.dart` names what owes one and why, and the suite prints both counts (`BURN-DOWN clauses proven: N of T server-proven: M of T`). Start with citations that name a live pack test but carry no `clauses:` list, reading each `proves:` first — some are unpinned on purpose. It includes the three crypto-agility matrices [`acceptance.md` section 17](acceptance.md#17-g2--crypto-agility--add-never-replace) specifies, whose harness is unbuilt: `_apsk` sign and verify (UC-G2.3, UC-G2.7, UC-G2.8), the pairwise substrate (UC-G2.1, UC-G2.4) and the nskey advertisement (UC-G2.2, UC-G2.10, UC-G2.11), each self-to-self and self-to-other against an advertiser offering one algorithm, both, or the other, one namespace per variation; a one-entry `rsa2048` `_apsk` serialises as a bare string, so one entry and two are different wire shapes. | Nothing |
| **publish at_client_skills 1.4.0** | The only package of the 4.0.0 set not on pub.dev, which tops out at 1.3.0. It teaches the `Atsign` verbs and at_client_flutter 2.0's dialogs, both published 2026-11-04; its CHANGELOG heading's date moves to the day it ships. | the package moving to the atsign.org publisher, then gkc — publishing is his act |

### P1 — must do

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **the upgrade guide has no retrofit clean-up** | Add to [`docs/upgrade-to-4.md`](../../upgrade-to-4.md) section 5 the clean-up [ruling 118](detail/decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27) names and ruling 41 item 7 routes to the guide, as at_server #2797 left it: archive the upgraded `.atKeys`; destroy pre-PQ copies, which hold the legacy encryption private key and, for a fully privileged predecessor, a credential that stays live; a predecessor that is not fully privileged is revoked as superseded at its successor's first authentication; and `enroll:revoke` cascades to descendants, so it is for compromise, never for clean-up. | Nothing |
| **the upgrade guide has no rollout recipe for application owners** | Add to [`docs/upgrade-to-4.md`](../../upgrade-to-4.md) the only mitigation for the repopulation window after an nskey rotation: gkc's two-rollout recipe (rollout 1 mints old and new and seals to old; rollout 2 mints and seals to new), the two levers `keyEstablishmentAlgorithms` and `sealsToKeyAlgorithms` moving in different releases, and the English-to-French analogy (gkc, 2026-11-07: it goes in the upgrade guide). | Nothing |
| **step 3 of a signing migration has no lever** | at_client's own verifiers — `verifyEnvelope` and the online `verifyEnvelopeSignature` — take `strongestOf(shared)` with no accepted set, so a retired client data signing key stays a standing forgery surface ([ruling 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28)). Build the verifier-side set mirroring `keyEstablishmentAlgorithms`, the encryption side's accept lever: it narrows `shared` before `strongestOf`, refuses an empty intersection with a message naming both sides, and makes UC-G2.9 c3 provable, which `unprovableClauses` enumerates for that reason; `architecture_guard_test.dart` guards its absence today. Not every caller may be narrowed: verifying one's own advertisement is not the same act as verifying a peer's data. The public `verifySignedEnvelope` facade's caller floor, `minimumAlgorithm`, is separate work (plan-50d.61 in gkc's queue). | Nothing |
| [the four missing self-to-self mirrors](#the-four-missing-self-to-self-mirrors) | gkc ruled 2026-11-07 that all four become catalogue rows: write the mirrors of UC-A4.5, UC-A4.7, UC-A4.6 and UC-A4.3 and their scenarios, after re-checking the audit against UC-A3.6 and UC-A3.7, which the catalogue gained after it. The denominator rises, correctly. | Nothing |
| **`AtRpcClient.call` has no timeout, and overwrites a call whose id is still pending** | Request ids are random 53-bit integers ([ruling 151](detail/decisions.md#151-atrpc-request-ids-are-random-53-bit-integers-2026-10-05)), so concurrent requests no longer share one. What remains: `call` in `packages/at_client/lib/src/rpc/at_rpc.dart` takes no timeout, so a caller waits for ever on a responder that never answers, and it overwrites a pending completer rather than refusing an id already in flight. NoPorts uses it. | Nothing |
| **the client half of ruling 128** | `selfRetrofit` and `retrofitIdentity` still take a required `namespaces`, which a successor may not choose ([ruling 128](detail/decisions.md#128-a-retrofits-successor-holds-its-predecessors-grants-and-may-not-choose-them-2026-08-31)); the atServer half refuses, so this is cleanup. Both are exported through `at_client_mixins.dart` in published at_client 4.0.0, so in a 4.x release the parameter becomes optional, `@Deprecated` and ignored, and it goes at 5.0 (gkc, 2026-11-07). Re-derive the call sites rather than relying on a count. | Nothing |
| **`retiredAt` on the `_apsk` advertisement** | Ruled 2026-08-31: `ApskSigningKey` (at_auth's `apsk_advertisement.dart`) gains a retirement timestamp, stamped when an entry moves to `retired`, so a verifier can date a key. A wire and at-rest change to `_apsk`, so it must be additive — at_auth 4.0.0's reader has to keep parsing an entry that carries it — and the doc sweep and the atServer's tests move in the same change; a record's `createdAt` is a caller assertion, not a clock to design against. | Nothing |
| **a retrofit leaves the enrolment record memo stale** | `LocalSecondary.getEnrollmentDetails()` memoises the record, `_settleEnrollmentIdentity` fills it with the predecessor's, and `_rederiveFromEnrollment` never clears it, so the client runs as the successor while the record describing what it may do is the predecessor's — benign only because a retrofit copies grants verbatim. Clear the memo on re-derivation. | Nothing |
| **key packages and envelopes are APKAM-signed with `rsa2048` by default** | gkc ruled 2026-11-07 ([ruling 162](detail/decisions.md#162-the-2026-11-07-plan-review-settles-nine-open-questions-2026-11-07) item 7) that these defaults go, as [ruling 136](detail/decisions.md#136-at_auth-stays-posture-blind-and-both-its-doors-demand-the-algorithm-2026-09-08) removed two others: `enrollmentKeyPackageBuilder`'s `signingAlgo` in `enrollment_key_package.dart`, at_auth's `FirstEnrollmentRequest.signingAlgo`, and `signingAlgoOf`'s fallback in `resolved_signing_algo.dart`. The caller names the algorithm, or it follows the enrollment's own authentication key. | Nothing |
| **four refusals for two user errors, one of them uncatchable** | A sender that omits an algorithm and one that cannot implement it reach four refusals across three exception branches with contradictory advice, and `AtSigningVerificationException extends AtException`, so an app catching `AtClientException` misses one. Consolidate them; the supertype change is at_commons, and a published type's supertype is visible to every caller catching it. | Nothing |
| [14.44](#1444-residuals-from-the-at_chops-pr-review) | `XWingCore.combine` sizes its buffer from its inputs while writing at literal offsets, so an over-long component is silently truncated — reject wrong-length inputs up front; and at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence, amended into that section in place. | Nothing |

### P2 — should be done if there is time

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **a two-member `dataSigningKeyAlgorithms` signs twice** | `signEnvelope` signs once per key it is handed and `ApkamSigning.signingKeys` hands it every held one, so an app naming two algorithms emits two signatures and gets only the weaker one's protection, since a stripped stronger signature leaves the weaker verifying ([ruling 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28)). Narrow the writer so a two-member set holds both keys and signs with the strongest; keep the multi-signature reader (`SignedEnvelope.fromJson`'s differing-`enid` and differing-`typ` refusals stop an entry being appended in flight); re-point the four tests that emit two signatures; and say in `dataSigningKeyAlgorithms`' dartdoc what a second algorithm does and does not buy. No posture and no library code names two today. | Nothing |
| **an APKAM rotation through `enroll:update` is never persisted** | `EnrollmentUpdateRequest.apkamPublicKey` can move an enrollment onto a new authentication keypair and nothing writes that keypair to a keyfile, so a rotation the atServer accepts and the client never saves locks the enrollment out; no production caller rotates it today. Owed in order, as [ruling 97](detail/decisions.md#97-a-keyfile-status-a-build-has-never-seen-is-read-not-refused-2026-08-14) ordered it (two-phase: file the new keypair staged, promote it when the atServer accepts): a staged status the rotation writer can use (`CryptographicMaterialStatus.pending` exists, defined for a keypair awaiting approval), a writer that persists before it promotes, then a live arm driving an enrollment and a mid-run rotation on a CRAM-only virtualenv Atsign. | Nothing |
| **the primary enrollment gets no revocation backstop** | gkc ruled 2026-11-07 ([ruling 162](detail/decisions.md#162-the-2026-11-07-plan-review-settles-nine-open-questions-2026-11-07) item 6, amending [ruling 130](detail/decisions.md#130-a-revocation-is-discoverable-per-namespace-and-rotates-unconditionally-2026-08-31) point 8) that it does. `NskeySeeding.rotateIfRevoked` skips a client with no enrollment id or `primary`; make that one predicate cover it, and move UC-G2.5's clause with it. The NOTE beside the skip says the atServer will not answer about the primary enrollment and the lookup's verb is APKAM-gated, so check that first: the atServer may owe a half. | Nothing |
| **arm 1 asserts 2 of its 14 rows** | `tests/at_functional_test/test/pq_stage_arm_test.dart` asserts UC-C1.1 and UC-C1.2 only; the other 12 rows [`acceptance.md` section 14](acceptance.md#the-rows-arm-1-owes) lists each owe a per-posture live cell in it, citing the file from the row's `provenIn`. UC-C1.4 also needs cells that vary `keyExchangeMode`, which arm 1 holds constant today. | Nothing |
| **switch `_enrollmentById` to `enroll:fetch`** | at_server 3.16.5 returns `metadata` on `enroll:fetch`, but `EnrollmentServiceImpl._enrollmentById` still filters an `enroll:list` roster client-side for both of `approve`'s reads. No atServer older than p3.16.5 is running (gkc, 2026-10-14), so switch with no fallback, reading an absent `metadata` as a refusal rather than as empty. | Nothing |
| **client paths read the whole roster to find their own record** | `ownGrantsOf` (behind `NskeySeeding.authorisedNamespaces` and `KeyPackageMinting`), `selfRetrofit`'s signing-root step, `EnrollmentRecordPrivilegeResolver`'s own-id check and `NskeyRotation.revokeEnrollmentAndRotate`'s own `__manage` check each fetch every enrollment to read one record of their own; redirect them to the memoised `LocalSecondary.getEnrollmentDetails()` (an `enroll:fetch`), checking whether `selfRetrofit`'s freshly opened client can share the memo. On a grown roster each costs what the approval used to — 46.6s measured. | Nothing |
| **`CkManager`'s missing-cut-time guard cannot fire** | `CkManager.ensureCurrent` returns early when `ContentKeyCache.currentCutAt` is null, but `putAsCurrent` always records a cut time, so the branch is unreachable. Delete the guard and its NOTE (making the cache durable is a feature, not this). | Nothing |
| **there is no supported way to wait for the PQ startup tail** | Nothing on the `AtClient` interface says when the unawaited PQ startup has finished; the live packs reach through `pqBootstrap.startupComplete`, which its dartdoc reserves for tests. `ensureReachable` and [ruling 160](detail/decisions.md#160-a-write-made-before-start-up-has-seeded-waits-for-it-2026-11-01)'s wait cover reachability and early writes; decide whether the interface also carries a startup-complete signal. | gkc |
| **at_client README does not carry the send/receive asymmetry** | `packages/at_client/README.md` names `ensureReachable` and says when a write after opening waits, but not the asymmetry an app meets first: you can send the moment you are up, and peers cannot seal to you until your key is published, which a process can exit before. `ensureReachable`'s dartdoc says it; decide how much belongs in the README, then write it. | Nothing |
| **a store write in flight when `stop()` lands still reaches the closed store** | The stopped-flag guards cannot reach a write that already passed them, so a pull-cursor or notification-watermark write can still reach the store after `stop()` has released it (measured in September as `Box not found` lines after `closeAll()`). Make `stop()` drain in-flight writes before it returns — a lifecycle change, so all four live packs. | Nothing |
| **the conveyance catch still swallows too much** | `SymmetricAesGcmProvider._resolveFromConveyance` rethrows decryption, state, provider and stop failures and treats a missing key as absent, but a final broad `catch` remains, so anything else reads as no conveyance. Probe what an absent record throws on the local and the remote leg, then remove the final `catch`. | Nothing |
| **secret-sharing envelope lifetimes are unpinned and unvalidated** | `PairwiseSecretSharing.envelopeTtl` (7 days) has no test pinning its default and no validation — a `Duration` under a millisecond sends `:ttl:0`, which the atServer reads as never expiring — and one assignment on the `AtClientSecretSharing.forClient` instance changes it for every envelope the SDK sends. The wake-up's `notificationExpiry: envelopeTtl` is unpinned too and falls back to 24 hours if dropped; and an envelope `_consume` rejects is retried every sweep, once a minute, until its ttl ends. | Nothing |
| **a missing `_apsk` is looked up again on every verification** | `EnvelopeSigning` caches a found `_apsk` for five minutes per AtClient but not a miss: each verification of something signed by a revoked, deleted or unknown enrollment makes up to three lookups (`.a.__e`, then `.r.__e` and `.d.__e` in `withdrawnApskLocation`), and nothing remembers the answer. Raised by gkc on 2026-10-10, ruling the at_server#2831 spec. | Nothing |
| **a String `apsk` on any enroll verb returns an internal error** | at_commons' generated `_$EnrollParamsFromJson` (`enroll_params.g.dart`) casts `apsk` and `apskLegacy`, and at_server calls `EnrollParams.fromJson` before validation and before the OTP check, on a verb an unauthenticated connection may send, so `"apsk":"x"` answers a Dart type-cast message instead of an `IllegalArgumentException`. Fix it in at_commons. | Nothing |
| **key transparency for signing roots** ([#2293](https://github.com/atsign-foundation/at_client_sdk/issues/2293)) | Clients fetch peer keys through their own atServer and check an advertisement against an `_apsk` the atServers also serve, so key authenticity rests on the atServers, in both directions of an Atsign's traffic ([design section 7.1](design.md#71-what-the-atservers-are-trusted-for)). Two steps move the anchor outside them: first, pin a peer's signing root on first contact and check every later advertisement through the chain back to it (`verifyChain` walks a chain, and its one production caller, `Enrollments.anchoring`, walks only the client's own Atsign's); then publish each signing root to a transparency log on the atDirectory ([section 7.5](design.md#75-key-transparency-on-the-atdirectory)), so first contact is checked too. The second step is multi-repo. Invitations can authenticate their own first exchange with a password-authenticated key exchange keyed on the code, as #2293 notes. | gkc scheduling it |
| **content-key conveyances carry no sender signature** | `pqSeal` authenticates no sender and nothing signs a content-key conveyance, so the sender of an nskey data value rests on the atServers alone, self-data included ([design section 7.1](design.md#71-what-the-atservers-are-trusted-for)). Signing them means each conveyance carries the writer's APKAM signature, and a reader refuses one that carries none (gkc, 2026-10-08). Deferred beside key transparency: until an independent anchor exists, a signature moves the sender's authenticity onto an `_apsk` the same atServers serve, and `getApkamPublicKey` fetches `_apsk` remote-only, so offline reads after a restart need verification persisted locally. | A ruling on revoked signers: refusing them makes every content key a revoked device cut unreadable, and accepting them keeps trusting a lost device's writes indefinitely |

### P3 — nice to have, or in another repo

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **a pull cut by `stop()` keeps none of its batches' progress** | `_syncFromServer` persists the pull cursor once, in its `finally` after the last batch, and `persistPullCursor` skips the write once the service is stopped, so a client stopped mid-pull re-pulls from its previous cursor (twenty clients in one CI job each pulled 711 commits from `-1`). Persist after each batch. | Nothing |
| [the registrar certificate test](#the-registrar-certificate-test) | Three arms against a self-signed certificate on loopback — the one behaviour change in the registrar client with a security consequence and no test. | Nothing |
| **a sequential, abort-on-failure `batch`** | A protocol enhancement (gkc, 2026-08-27): `batch` runs its commands in order but carries on past a failure; an abort-on-failure form would close the mint locks' take-to-write windows structurally. Multi-repo — at_commons, at_client and at_server in one sweep. Its two prerequisites, the handler's silent drops, landed in at_server#2906 (merged 2026-11-05, not yet released). | A design and a cross-repo sweep |
| [the `monitor:` verb has no acknowledgement](#the-monitor-verb-has-no-acknowledgement) | A protocol seam across three repositories; the caller-side mitigation is built and live-proven. | gkc scheduling it |
| [atServer outbound connection pooling](#atserver-outbound-connection-pooling) | In `at_server`, and asked for as a discussion rather than a change. | gkc scheduling it |
| [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | It gates the post-R-2 stop-release, and until it closes `mintLegacyMaterial: false` is not to be recommended to anyone. Both moves it needs are unscheduled, one of them B-3 phase 1, which is parked. | two unscheduled moves its body names |
| [14.29](#1429-the-residuals-1425-surfaced) | S-3's keychain round-trip on a real device; SS-2's `__ssenv` auto-notify is deferred, not owed. | an `integration_test` harness in at_client_flutter |
| **public-data signature verification** | Deliberately outside the catalogue (gkc, 2026-08-23): every posture signs public data into `metadata.dataSignature` (`_signPublicData` in `put_request_transformer.dart`, an RSA-2048 signature by the legacy data signing key (the Atsign's encryption private key, whose public half is `public:publickey`)) and nothing anywhere verifies it — not at_client, not any atServer — so a signature nobody checks is emitted knowingly. The design sketched for it ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)): sign with the enrollment's client data signing key in the `_apsk` envelope form; the verifier walks the signer's `_apsk` through the approval chain to `pq_signing_root` (`PqSigningChain.verifyChain` in `pq_signing_chain.dart`); verification runs automatically on public reads, non-fatally, with the outcome exposed to the caller, and needs the signer's `_apsk` cached; and the verifier reads both signature forms, the legacy `dataSignature` checked against `public:publickey` permanently, because every public record a released at_client signed sits on a live Atsign. | a design |
| **a latent sync-queue defect** | The queue keeps one entry per key and the last operation wins, so a local `putMeta` landing after a local value put and before the drain pushes only `update:meta`, and the value never reaches the atServer; `AtClient.putMeta` has no SDK caller today. Not PQ. | Nothing |
| **invitations example: two loose ends** | First, Home's `_watch()` subscriptions stay on the replaced client after "Accept as" switches Atsign; Home's timer keeps the passes running meanwhile. Second, `demo/demo.sh --record` has never run end to end: its device and size lookups were probed, but a shell whose ffmpeg lists no screen could not record. | Nothing |
| **the retrofit lock waits less than its own staleness** | `fileRetrofitSerializer` gives `AtKeysFileLock` a 30s timeout under a 2min `staleAfter`, so a waiter on an abandoned `.retrofit` lock gives up before it could break it. The lock's rule is now the reverse: a timeout longer than `staleAfter`, with a live holder kept fresh by its heartbeat. | Nothing |
| **published versions the tree has moved past without a bump** | A version on pub.dev says nothing about whether the tree still matches it, so diff the archive (`https://pub.dev/api/archives/<pkg>-<version>.tar.gz`) against the package before calling it current. Measured 2026-10-03, and not re-measured since: at_chat_flutter's `lib/` moved onto at_client_flutter `^0.1.2` under its published 3.1.0; at_follows_flutter fixes a log typo; and at_contacts_group_flutter, at_events_flutter, at_location_flutter, at_notify_flutter and at_sync_ui_flutter differ in pubspec, README, tests or examples only. Each ships only with a version bump. Not PQ. | gkc — a bump is his call |
| **NoPorts: a device-level nskey as the PQ-capable signal** | In `sshnoports`, not here (gkc, 2026-10-04; [ruling 146](detail/decisions.md#146-keys-an-app-publishes-below-its-grants-are-its-own-and-ensurereachable-reports-holding-them-2026-10-04)); a draft branch `gkc-pq-device-key` exists with no PR. A client treats a daemon as post-quantum-capable when an nskey is advertised at exactly `<device>.sshnp` on the daemon's Atsign; old daemons never publish one, so a fleet can mix. A daemon runs a seeding posture on an enrollment whose record carries a key package (on the primary enrollment `ensureReachable` answers `noKeyPackage` and mints nothing), calls `ensureReachable('$device.sshnp')` at every start, and replies in the scheme the request arrived in, passing the request's `AtNotification.receivedUnder` as the reply's `cryptoProviderId` ([ruling 149](detail/decisions.md#149-how-a-shared-value-was-protected-is-read-from-its-metadata-and-a-reply-goes-in-kind-2026-10-05)), rather than asking whether the client's Atsign advertises `sshnp`. A client checks that exact level with `PublishedNskeyKeyRing(atClient).publishedAdvertisement(<daemon>, '<device>.sshnp')`, which reads the record from the atServer and verifies it, since `CryptoRuntime.isReadyFor` and the resolver fall back to `sshnp`; sends legacy for every message to a daemon without one, since `ping.<device>` and the rest of `sshnp` seal to the `sshnp` key; and sends a request post-quantum only after `ensureReachable('sshnp')` reports `holdsPrivate`, so it can open the reply. Under `pqReady` a message is sent post-quantum with `cryptoProviderId: symmetricAesGcmCryptoProviderId`, and legacy with `CryptoRuntime.legacyProviderId`. A daemon reinstalled under a reused device name is conveyed the old key at approval only when its approver holds it ([ruling 147](detail/decisions.md#147-an-nskey-reaches-every-enrollment-with-access-to-its-namespace-when-it-is-minted-and-when-that-enrollment-is-approved-2026-10-04)), and one whose own result says it does not hold its device key's private has none: nothing in the SDK re-fetches or replaces that key at start, so NoPorts must not reuse device names across enrollments. | Nothing |
| **each e2e run can restart the shared atServers under another run** | `end2end_tests_prep` runs trunk's `tools/<host>/update_ce2e_images.sh` on every run, and its `docker service update --image` replaces an @ce2e service whenever the `dev_env` or `canary` tag has moved since the last update, dropping the connections of any other run's tests on it. In the 100 runs from 2026-10-07 to 2026-10-13 six prep jobs replaced a service, none while another run's e2e jobs were running; what a replacement costs a run mid-test is unmeasured. Decide whether the roll leaves the per-run prep, or shares a concurrency group with the e2e jobs. | Nothing |
| **the e2e pack hears other runs' notifications** | Overlapping runs of one e2e job notify between the same two Atsigns. `notify_with_isolate_test.dart` sends a fixed key and value and its receiver keeps any notification carrying that value, so it can pass on another run's; `key_stream_test.dart`'s KeyStream, Iterable and Map groups subscribe to the whole `e2e_test` namespace, so another run's notification landing in the milliseconds before their own events fails `emitsInOrder`. Make each run's keys, values and regexes run-unique. | Nothing |
| **the PQ CI jobs could run on the published image** | The functional, e2e post-quantum and onboarding-CLI jobs pin `atsigncompany/virtualenv:dev_env` so they run against trunk. From p3.16.5 the published `vip` verifies ML-DSA PKAM and stores enrollment metadata: against it on 2026-09-30 the onboarding-CLI pack passed 21/21, the e2e post-quantum set 21/21 and `enrollment_key_package_live_test.dart` 3/3. Whether any job moves to `vip`, or keeps tracking trunk on purpose, is a ruling. | gkc's ruling. |
| **"build every EE from a named ref" rests on less than it did** | The acceptance catalogue's EE ruling was argued from the published EE lacking ML-DSA PKAM and being rebuilt only monthly. p3.16.5 removed the first reason, and at_server has published `ephemeral:dev_env` per trunk commit since at_server#2821. The ruling now rests on reproducibility alone; whether it stands is a ruling. It governs the catalogue's arms, not the invitations example, whose `ee/up.sh` defaults to `ephemeral:latest` on purpose. | gkc's ruling. |
| **`enrollmentlId` is misspelled in published public API** | The field is declared in at_commons' `pkam_verb_builder.dart` and read in at_auth's `at_authenticator.dart`; at_commons 5.25.0 is published with it, so the rename is breaking and rides an at_commons major. Rule it either way. | gkc |
| **at_server's mldsa65 dispatch comment is stale** | In at_server, not here: `apkam_signature_verifier.dart` and its test say `AtChopsImpl` "selects `MlDsa65PureDartAlgo`, then calls the deprecated `verify()`" for mldsa65, while at_chops dispatches to `PkamMlDsa65SigningAlgo`, whose verify is synchronous. Two sites. | Nothing |
| **a rotating Atsign could tell its senders** | A sender learns of a rotation only by re-resolving the advertisement, up to 30 minutes of ttl plus grace later, and keeps sealing to the superseded generation meanwhile. Every `.__ck.` conveyance record is addressed to a sender, which suggests a rotating Atsign can enumerate exactly who must re-cut; probe that scan before designing on it. | Nothing. A probe first |
| **the functional pack's CI time stepped up about 20%** | Every run carrying `9c84011df` (the 2026-09-07 trunk merge-back) measured 8m23s–11m35s on stable against 5m30s–9m52s before it; the posture flip is not the cause. Decide whether about two minutes a run is worth chasing; a bisect now has to re-measure both arms with today's pack, since the pack and its CI jobs have changed since. | Nothing |
| **`useRemoteAtServer` on a key another Atsign shared failed `key not found`** | 115 failures in one run on 2026-09-08. The row's earlier account of the mechanism does not match the code: `LookUpBuilderManager.get` builds a `lookup:`, not an `llookup`, for a key another Atsign shared, and `GetRequestOptions.useRemoteAtServer`'s dartdoc already says such a read always goes to the atServer. The cause is unmeasured; re-run the scenario with the verb `get` builds printed and which atServer answered. | Nothing |
| **`runCliCommand` streams the CLI child's output unprefixed** | `tests/at_client_cli_functional_tests/test/utils/at_client_cache.dart` writes the child's stdout and stderr verbatim, so two processes' lines cannot be told apart. Prefix or pid-tag them and say so in its dartdoc. | Nothing |
| **test-helper cleanup: one `EnrolledClient`** | Port the e2e `EnrolledClient` copy (it lacks `signingAlgo`, `atKeysIo` and `keyExchangeMode`, and keeps a plain `kpid` field), correct its `enrollmentId` dartdoc, which says it hard-codes `rsa2048` while the code hard-codes `mldsa65`, run the e2e pack, and move what is shared into a never-published `tests/packages/test_helpers`. | Nothing |
| **`notificationStatusEnum` is not an outcome, and its name says it is** | A dartdoc fix: with `checkForFinalDeliveryStatus: false`, or when a send fails before reaching the atServer, the field reads `undelivered` whatever happened and only `atClientException` distinguishes; the `on AtException` handler's comment says it sets `errored`, a value the enum lacks. Fix the comment first, then qualify the field and `NotificationResult`. | Nothing |
| **a pq enrolment's post-approval collection is unmeasured** | A PQ enrollee collects the key its approver encapsulated to its key package after approval, where a legacy enrollee is done at approval; the enrolment APIs already say the collection happens. Measure what it costs and decide whether they also state that. | Nothing |
| **`KeyUtil` has zero callers** | at_commons' `KeyUtil` (`lib/src/keystore/at_key_util.dart`) has no caller and no barrel exports it, so it is not published API: delete it. | Nothing |
| **`pqSealDefaultVersion` may not deserve to exist** | Nothing reads it — `pqSealToBase64` makes `version` required and both call sites pass a negotiated value — and `0x02` and `0x03` differ by KEM, so a wrong default is an unopenable record rather than a downgrade. Delete it and make `version` required on `pqSeal`/`pqOpen`, a public at_chops API change. | Nothing |
| **`provenIn` cannot catch a rename it is not the citation for** | It matches only its `testName` argument, and `proves:` prose that names sibling tests is matched against nothing, while `proven_elsewhere.dart`'s library dartdoc promises "rename or delete the live test and this goes red". Stop naming tests in `proves:`, or extend the check to quoted names inside it. The same check takes the test name as a bare substring anywhere in the file, so a comment or a `group(` name satisfies it; requiring a `test(` token fixes that, but not naively, because many declarations put `test(` and the name on separate lines. | Nothing |
| **two public constructors take a parameter type the barrel does not export** | `PqSigningRoot` and `PublishedNskeyKeyRing` take a `MintLock`, which `crypto.dart` does not export, so a caller outside the package cannot name the argument. It was left because both parameters exist for tests and the surface was `@experimental`; the marker went in 4.0.0, so decide whether to export the type or hide the parameters. | gkc |
| **atGettingStarted's `at_activate.dart` imports a deleted file** | In `cconstab/atGettingStarted`, not here: `at_dart/bin/at_activate.dart` imports `package:at_onboarding_cli/src/activate_cli/activate_cli.dart`, gone since at_onboarding_cli 1.17.0. Delete the wrapper and use the shipped `at_activate` binary, which now comes from at_client_cli. | Nothing |
| **an abandoned nskey mint grows the keyfile** | An abandoned mint (a crash between filing and publishing, or the lease-expiry abandon) leaves its private in `.atKeys`; since UC-A3.7 the next cold-start mint retires it rather than leaving it active, but retired material is never removed, so each abandoned mint still grows the keyfile. Decide whether a retired private that was never published may be dropped. SS-4 resume was ruled NO RESUME. | the decision (gkc) |
| **`docs/projects/` has no index of its live projects** | pq, wasm, bdd, deprecations, the at-lookup consolidation, client-cli, client-lifecycle, keystore-primitives and the knowledge base each keep their own list, and this file's header names only some of them; a ruling on where an index lives. | gkc |
| **an `at_lookup` unit test resolves a real atDirectory** | `secondary_address_cache_test.dart` looks up `@cicd1` at `root.atsign.wtf:64`, Atsign's staging atDirectory, from the at_lookup unit pack (its own group name says move it). Move it to a functional pack with a longer timeout. | Nothing |
| **the local e2e fixture cannot reproduce an APKAM enrollment-id defect** | `local_setup.dart` mints every local keyfile from `at_demo_data` with no enrollment id while declaring `authType: 'apkam'`, so a local run passes where CI's `end2end_test_14` catches an enrollment-id defect. Enrol for real, or say in its dartdoc that it cannot. | Nothing |
| **`public:publickey`'s `ttr -1` is unpinned** | `AtAuthImpl.completeActivation` publishes the encryption public key with `ttr -1` so peers may cache it indefinitely (at_libraries#297, at_server#1226); the functional test that asserted it lost the assertion in `9b55a2365`, and nothing has checked it since. Pin the built command. | Nothing |

### The four missing self-to-self mirrors

**Ruled 2026-11-07: all four become catalogue rows** (gkc, [ruling 162](detail/decisions.md#162-the-2026-11-07-plan-review-settles-nine-open-questions-2026-11-07)
item 8). Landing them raises the burn-down's denominator with the new clauses
unproven, so the percentage falls — the direction it should move, since the
clauses were always owed.

**The rule this comes from** (gkc, 2026-08-27): a use case for `put` or `notify`
— or for the receiving side, `get` or notification receipt — is about **self to
self** *or* **self to other**, never both at once. And where one direction has a
row, so should the other.

Auditing every put/notify/read row against that, five pairs already hold:
UC-A3.1↔UC-A4.1, UC-A3.3↔UC-A4.2 (with UC-B4.1 carrying the fallback),
UC-A3.4↔UC-A4.4, UC-B3.1↔UC-B4.3 and UC-B3.2↔UC-B4.4. UC-A3.2 is seeding and
UC-A3.5 is the advertisement's shape, neither being a write row. **Four
self→other rows have no self→self mirror:**

| Would mirror | What the self row would assert | What the tree can tell apart |
| ------------ | ------------------------------ | ---------------------------- |
| **UC-A4.5** — a sender follows the recipient's advertised algorithm, not its own preference | A self write seals under the algorithm **this Atsign's own published nskey advertises**, even when `keyEstablishmentAlgorithms` names a different one. Fixture: a published X-Wing nskey and a preference configured for `ml-kem-1024` | `NskeyResolver.resolve` reads the published advertisement and then filters by `sealsToKeyAlgorithms`; a build that consulted the *minting* preference instead would be wrong. ⚠️ For a self write both values belong to the same Atsign, so **a client reading the wrong one is invisible** |
| **UC-A4.7** — no mutually supported construction is a refusal, not a guess | A client whose `sealsToKeyAlgorithms` has been narrowed past what its **own** advertisement offers is refused, and the refusal says so rather than reporting a cold start | `NskeyResolver` throws `AtEncryptionException` rather than walking on, and its comment names the case: a narrowed algorithm list reads as the recipient having published nothing. Nothing exercises it for self |
| **UC-A4.6** — the construction is negotiated from `suites` | A self write against this Atsign's own advertisement listing only a retired construction is refused, and one listing the current construction gets the matching version byte | `NskeyProvider._sealVersionFor` intersects what the build can open with the advertisement's `suites`; for self that advertisement is one this Atsign wrote, so a mismatch means an advertisement older than the build |
| **UC-A4.3** — multi-enrollment both ends | Every authorised enrollment of this Atsign reads this Atsign's own self data | Largely proven already: UC-A3.1's Given has `alice1, alice2` both holding the private, approval-time conveyance is UC-A2.3, and an enrollment that missed the mint healing from a holder is UC-B5.11. The row can cite those |

### The registrar certificate test

**The registrar's switch to validating TLS certificates is untested, here and in
CI.** `RegistrarService`'s default client is a plain `package:http` client that
validates, with the bypass behind `RegistrarIoClient.allowBadCertificates`, off
by default and shouted when used. at_client_cli has a second such opt-in,
`OnboardingUtil.allowBadCertificates`, also untested. `RegistrarIoClient.create()`
has no in-tree caller — it is a public opt-in for consumers, which is
deliberate, so do not delete it as dead code.

**The shape that works:** mint a certificate at test time with
`openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=localhost` (**do not commit a
PEM** — push protection blocks private keys), serve it with
`HttpServer.bindSecure`, and point `RegistrarService` at `localhost:<port>`, which
`Uri.https` accepts as an authority. `packages/at_client_cli/test/registrar_debug_logs_test.dart`
already mints a certificate with the SAN, `serverAuth` and `keyUsage` extensions
macOS needs. **Three arms, and the third is the positive control that proves the
server is up**: the default client refuses, `RegistrarIoClient.create()` with
the flag off refuses, and with the flag on succeeds — without it a refusal is
indistinguishable from a server that never started, because `package:http`
wraps connection-refused in the same `ClientException`. The test needs
`import 'package:at_auth/at_auth.dart';`, which is what exports
`RegistrarApiEndpoint`.

### The `monitor:` verb has no acknowledgement

**A protocol seam across three repositories.** A client writes `monitor:` and
there is nothing to read back — at_server's `MonitorResponseHandler` returns the
empty string on success — so it cannot tell acceptance from refusal, and reports
a connection as up the moment the command is *written*.

Specified upstream as
[at_protocol#367](https://github.com/atsign-foundation/at_protocol/issues/367)
with three open sub-issues: at_commons
[#2175](https://github.com/atsign-foundation/at_client_sdk/issues/2175) (a
`prompts` parameter on the verb, opt-in and additive, and it ships first),
at_server [#2764](https://github.com/atsign-foundation/at_server/issues/2764)
(answer the command, and terminate every notification with a prompt), and
at_lookup
[#2176](https://github.com/atsign-foundation/at_client_sdk/issues/2176) (send it,
wait for the answer, frame on the prompt).

⛔ **A correction to that specification, to settle BEFORE anyone builds it.** #367
says the acknowledgement lets "a refused `monitor:` be reported as a failure".
`MonitorVerbHandler.processVerb` refuses an unauthenticated connection and an
invalid regex, and otherwise subscribes the connection; the refusal of a
notification the enrollment may not see happens per notification inside
`_sendNotification` via `isAuthorized`, dropping each one with a server-side
warning the app never sees. A replay does not rescue it either — replayed
notifications go through the same check. So the acknowledgement ALONE does not
fix the case #367 leads with; at_server must also decide that refusal **at
`monitor:` time**. #2764 gestures at this ("A refusal must be answerable too") as
an aside rather than as the work.

**The caller-side mitigation is built and live-proven** — `AtRpc.ready()` and
`AtRpc.listenerReadyTimeout`, with `sendRequest` awaiting readiness when
`isClient`. That closes the exposure for at_client's own callers; it does not
close the protocol gap.

### atServer outbound connection pooling

**In another repo (`at_server`), and gkc asked for it as a discussion rather than
a change** — 2026-08-24, when he took pool keying out of the concurrency fix:
*"I'd rather serialize on a single connection for now, and have a longer
discussion on how to handle outbound connection pooling and concurrency at a
later date"*. Recorded so the deferral does not read as a decision.

**What that discussion has to weigh:**

- Every relayed lookup to a remote Atsign serialises behind every other one on
  one pooled client's `_requestResponseMutex`, whose queue is unbounded by
  design, and a request queued on the mutex is waiting before its read budget
  (30 s in all, 10 s of silence) starts.
- `InboundConnectionImpl.equals` matches on remote **address and port** rather
  than object identity, so keying on "the real inbound connection" is not the
  identity keying it sounds like.
- `PolVerbHandler` holds a third `DummyInboundConnection`, so pol's
  `lookUp`/`plookUp` share a pooled client with relayed lookups at
  `handshakeRequired: false`.

The four residual findings once recorded here were fixed in
[at_server#2773](https://github.com/atsign-foundation/at_server/pull/2773)
(merged 2026-08-28): `poolSize` enforced across pool keys, an evicted client
closed, framing read from the byte stream, and reads bounded by an inter-chunk
gap as well as a total.

⛔ **Changing `DummyInboundConnection.equals` must not be folded in** —
`NotifyConnectionPool.getOutboundClient` builds a fresh dummy per call and relies
on that match to reuse a connection at all, so identity equality there would
open a connection per notification.

### 14.29 The residuals 14.25 surfaced

**S-3 — a keychain round-trip on a real device.** Nothing exercises `.atKeys`
through a real device keychain: at_client_flutter's keychain tests mock the
platform channel (`packages/at_client_flutter/test/keychain_io_impl_test.dart`,
`test/keychain_storage_test.dart`), and the only `integration_test/` in the tree
is the invitations example's, which drives file-backed keys. Unblocking it means
standing up an `integration_test` harness in at_client_flutter first.

**SS-2 / DEP4 — `__ssenv` auto-notify: deferred, do not build.** The
2026-08-03 ruling took DEP4 off SS-2 once the correctness argument behind it
was withdrawn, so what remains is a pure optimisation — an atServer that emits
the wake-up itself on a put to an `__ssenv` key, after which senders can set
`sendWakeUpNotification = false` (`PairwiseSecretSharing`, whose dartdoc already
states the coupling). It needs parity across every atServer implementation in
one sweep. Re-derive the starting state rather than quoting it —
`git -C ~/dev/atsign/repos/<repo> grep -c "__ssenv" <ref>` per repo, each run
beside a control that matches, naming the ref because these checkouts sit on
feature branches.

### 14.12 A `mintLegacyMaterial:false` Atsign cannot write a public record

⛔ **It gates the post-R-2 stop-release (gkc, 2026-08-23).** Until it
closes, `mintLegacyMaterial: false` must not be recommended to anyone. The
flag is honoured at activation — no RSA keypair is minted and no
`public:publickey` is published — but the resulting Atsign then cannot publish
anything, because **every public write is signed with the legacy encryption
private key**: `put_request_transformer.dart` `_signPublicData` throws
`AtPrivateKeyNotFoundException('Failed to sign the public data')` when it is
absent. The post-quantum path itself needs two public writes — the
enrollment's `_apsk` anchor to the signing root, and the nskey advertisement —
and both fail. Every posture sets `mintLegacyMaterial: true`, so only a caller
that opts out meets it.

**Owed, and neither move is scheduled here:** public-record signing moves onto
the ML-DSA signing root rather than the RSA encryption keypair — the same swap
inter-server authentication made — and self data moves off `selfEncryptionKey`
onto the nskey path (B-3 phase 1, [PARKED](#parked)). The stop-release cannot
ship before both, and [ruling
42](detail/decisions.md#42-the-to-define-list-ruled-2026-08-05) item 10 has
the release default resolving null→false in the major after R-2.

**Pinned live:** the opt-out arm of
`tests/at_functional_test/test/pq_legacy_interop_live_test.dart` expects the
public write to fail with that exact reason, so whoever fixes this gets a red
test naming the row that was waiting for it.

### 14.44 Residuals from the at_chops PR review

**at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence,** amending the
3.6.0 section in place rather than opening a new heading. The consequence to
state, one sentence beside the `0x01` removal: two installs of released
at_client 3.14.0, resolved either side of at_chops 3.6.0 reaching pub.dev,
cannot read each other's pairwise `__ssenv` envelopes in either direction for
the envelopes' 7-day ttl — at_chops 3.5.0 and older hardcode seal version
`0x01`, and 3.6.0's open set is `{0x02, 0x03}`. The durable record is [ruling
110's addendum](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18).

**`XWingCore.combine` writes at hardcoded offsets.** In
`packages/at_chops/lib/src/algorithm/encryption/x_wing_core.dart`, `combine`
sizes its buffer from the four inputs' actual lengths and then writes at
literal 0/32/64/96/128, so the two disagree for any component that is not 32
bytes. Correct for X-Wing today — every caller passes components whose lengths
the underlying primitives fix at 32. Measured rather than reasoned: a **short**
input throws `StateError: Too few elements` from `setRange`, so only an
**over-long** one is silently wrong — it truncates to 32 and leaves the
buffer's tail zeroed, yielding a shared secret neither party can detect is
wrong. Fix by rejecting wrong-length inputs up front against
`sharedSecretLength` — not by tracking offsets with a cursor — so the guard
states the contract instead of silently accommodating a violation of it.

## PARKED

Set aside deliberately. A row here exists to stop someone building it, so
the reason is the point of the row.

| Item  | What it is | Why it is parked |
|-------|------------|------------------|
| S-5 residual | **Two String vocabularies stay untyped** | ⛔ **Considered and left, not a task.** The keyId slot prefix (`auth`/`sign`/`root`, taken by `AtKeys.keyIdPrefix` and `isRoleKeyId`) is **not** a `CryptographicMaterialRole`: typing it as one was tried on 2026-08-22 and reverted when the compiler rejected every call site. `keyAlgo`, the secret-sharing protocol id, is a third vocabulary again. Recorded so the next reader does not re-derive that these are the same thing |
| B-3   | Stop **conveying** the legacy `selfEncryptionKey` | Narrower than it reads: the key's *use* is retired by the release cadence (R-2 flips `disallowLegacyEncryption`), so this is only relaxing `enroll:approve` to accept an approval that omits `encryptedDefaultSelfEncryptionKey` — every atServer implementation, one sweep — then ceasing to mint and convey it. Ecosystem-gated by [ruling 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05). Issue #2128 |
| KF-1  | `.atKeys`-at-rest protection + backup/restore | Not scheduled. Issue #2129 |
| R-2   | at_client 4.x and 5.0.0 posture defaults | In two stages across two majors ([ruling 138](detail/decisions.md#138-the-posture-ladder-moves-back-a-stage-2026-09-08)): **the default `PqPosture` becomes `pqReady` in a 4.x release after 4.0.0, and `pqActive` at 5.0.0** ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18) names the axes); 4.0.0 ships `legacy`. Pure default flips carrying no code of their own. Issue #2016, whose body still says the 4.0 default would be `pqReady`, which ruling 138's 2026-10-28 amendment reversed |
| D2-1  | Carve `at/pqmls` + D1-E shape fixes | D2 work, for that workstream's own list |

---

## Re-deriving the state

Run these rather than trusting a row. No figure lives here: the command is the
value, and a number written beside one has rotted every time. Every `dart test`
and runner line needs a scratch `HOME` (`env HOME=<scratch> PUB_CACHE=~/.pub-cache`),
and every `cd` runs in a subshell so the next line still resolves from the repo
root.

```bash
# The clause meter — proven and server-proven — prints on every run of the suite.
(cd packages/at_client && dart test test/acceptance --concurrency=1 | grep BURN-DOWN)
# Which rows owe live proof, which are exempt, which clauses cannot be proven, and why.
grep -n "^  'UC-" packages/at_client/test/acceptance/manifest.dart

# Whether each package's tree version is on pub.dev. The versions LIST, never `latest` — `latest` hides prereleases.
for pkg in at_commons at_utils at_chops at_lookup at_auth at_client at_client_cli at_onboarding_cli at_cli_commons at_contact at_policy at_client_flutter at_telemetry at_client_skills; do
  t=$(grep -m1 '^version:' packages/$pkg/pubspec.yaml | cut -d' ' -f2)
  printf '%-20s tree %-12s on pub.dev: %s\n' "$pkg" "$t" \
    "$(curl -s https://pub.dev/api/packages/$pkg | jq -r --arg v "$t" '[.versions[].version] | index($v) != null')"
done

# CI on trunk. CI's at_client job runs a bare `dart analyze` that reads benchmark/, which `dart analyze lib test` skips.
gh run list --branch trunk --limit 4 --json headSha,conclusion,workflowName \
  --jq '.[] | [.headSha[0:9], .workflowName, .conclusion] | @tsv'
# One job's rate over recent runs (functional_tests, pqe2e_tests, end2end_test_14).
for r in $(gh run list --branch trunk --workflow at_client_sdk.yaml --limit 20 --json databaseId --jq '.[].databaseId'); do
  gh run view "$r" --json jobs --jq '.jobs[] | select(.name|test("^functional_tests \\(")) | [.name,.conclusion] | @tsv'
done | sort | uniq -c | sort -rn

# The citation denominator. ⛔ rm first — provenIn APPENDS, and a stale file reads as twice the corpus.
L=<scratch>/cit.jsonl
(cd packages/at_client && rm -f "$L" && ACCEPTANCE_LEDGER="$L" dart test test/acceptance --concurrency=1 >/dev/null)
python3 -c "import json,sys;r=[json.loads(l) for l in open(sys.argv[1])];print(len(r),'citations,',sum(1 for x in r if not x.get('clauses')),'unpinned')" "$L"
git grep -c 'provenIn(' -- packages/at_client/test/acceptance | awk -F: '{s+=$2} END {print s}'   # the second derivation, +1 in proven_elsewhere.dart

# Acceptance: what is skipped, and on which blocker. Anchor on "}, skip:" — a bare "skip:" matches prose about skips.
grep -rn "}, skip:" packages/at_client/test/acceptance/*_test.dart
grep -n "blocked:\|owed:" packages/at_client/test/acceptance/blockers.dart

# The `legacy` vocabulary completion test, control first: the control line must print. Every
# `legacy` in Dart prose names its axis: the provider, the posture, `-encrypted` records, the
# keyfile document, or an enum value such as `EnrollmentKeyExchangeMode.legacy`.
printf 'the client writes legacy and stops\n' | perl -ne 'print "CONTROL OK\n" if /\b(writes?|written|stays?|stayed|remains?|remained|is|are|was|were|be|being|goes\s+out|went\s+out|keeps?\s+writes|falls?\s+back\s+to|fell\s+back\s+to|fallback\s+is|default\s+is|mode\s+is|refusing|under|proceeds)\s+legacy\b(?![-_\w])(?!\s*(provider|posture|-encrypted|material|peer|keys?|flat|fields?|mode|server|atServer|enrollments?|PKAM|pkam|credential|clients?|apps?|build|data|wrapper|ladder|route|path|encryption|era|stage|format|document|keyfile|verb|form|RSA|AES|crypto|behaviour|readers?|records?|value|pair|keypair|link|apsk|names?|alias|signing|auth|authentication|API|surface|onboard|secondary|stores?|shape|reads|writes?|by\b))/'
find packages tests -name '*.dart' -not -path '*/.dart_tool/*' -print0 \
  | xargs -0 perl -ne 'print "$ARGV:$.: $_" if /\b(writes?|written|stays?|stayed|remains?|remained|is|are|was|were|be|being|goes\s+out|went\s+out|keeps?\s+writes|falls?\s+back\s+to|fell\s+back\s+to|fallback\s+is|default\s+is|mode\s+is|refusing|under|proceeds)\s+legacy\b(?![-_\w])(?!\s*(provider|posture|-encrypted|material|peer|keys?|flat|fields?|mode|server|atServer|enrollments?|PKAM|pkam|credential|clients?|apps?|build|data|wrapper|ladder|route|path|encryption|era|stage|format|document|keyfile|verb|form|RSA|AES|crypto|behaviour|readers?|records?|value|pair|keypair|link|apsk|names?|alias|signing|auth|authentication|API|surface|onboard|secondary|stores?|shape|reads|writes?|by\b))/; close ARGV if eof'

# The rails. The exit code is the verdict, never the count. The format verdict comes from
# CI's Dart in Docker, run inside the package, never from the local formatter.
(cd packages/at_client && dart analyze && dart test --concurrency=1)
for p in at_auth at_lookup at_commons at_chops at_utils at_onboarding_cli at_cli_commons at_client_cli at_contact at_policy at_telemetry; do (cd packages/$p && dart test --concurrency=1); done
(cd packages/at_client_flutter && flutter analyze)       # `dart analyze` skips a Flutter package silently
for t in at_functional_test at_end2end_test at_client_cli_functional_tests at_client_cli_functional_tests_proxy; do (cd tests/$t && dart analyze); done

# The four live packs, each through its own runner (the atsign-live-testing skill has the fixture rules).
# Pin the image by building it from a ref you name: no label on at_virtual_env:local says which atServer it holds.
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_functional_test/runLocal.sh
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_end2end_test/runLocal.sh 26000 test -x pq
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_end2end_test/runLocal.sh 26000 test/pq -x legacy-server
VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip-p3.15.0 bash tests/at_end2end_test/runLocal.sh 26000 test/pq -t legacy-server
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_client_cli_functional_tests/runLocal.sh 47000
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_client_cli_functional_tests_proxy/runLocal.sh 48000
```

⛔ **There is no command for "which atServer build is in `at_virtual_env:local`".**
The image's `org.opencontainers.image.revision` label describes the published
base image, not the binaries compiled into it. Build from a ref you name:
`git -C <at_server> worktree add --detach <dir> <ref>`, compile
`at_secondary_server` and `at_root_server` with `docker run --rm -v "<dir>:/app"
-w /app/packages/<pkg> dart:<version> sh -c 'dart pub get && dart compile exe
bin/main.dart -o <name>'`, taking the Dart version from at_server's
`tools/build_secondary/Dockerfile` (a detached worktree, because the
in-container `dart pub get` rewrites `.dart_tool` with `/app` paths), copy both
into `tools/build_virtual_environment/ve/contents/atsign/{root,secondary}/`, and
`docker build` there.
