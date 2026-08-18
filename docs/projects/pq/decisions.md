# decisions.md — the ledger

Every decision this project has made, one row each. **The reasoning lives in
[`detail/decisions.md`](detail/decisions.md)**, under a `## <number>.` heading
matching the row.

This file is deliberately bodyless. Reading it, or grepping it, returns
headlines — so a decision you were not asking about cannot arrive in the middle
of unrelated work. Open the detail file when you want a specific ruling's
argument, and only then.

**Ruling numbers are permanent; headings are not.** The number is cited from
production dartdoc, from the four sibling docs and from `blockers.dart`, so a
ruling is never renumbered and never deleted. **Its heading states what the
ruling means now** — when an outcome changes, the heading changes with it and
every link is updated in the same edit. Keep headings short: they become URL
slugs, and a long one makes that sweep expensive enough to skip.

**Correct in place; do not append.** A ruling's body is the argument, not a
diary. New reasoning is added, but a claim the project has since falsified is
**replaced** — a stale sentence left standing under a ⚠️ is read as current by
the next session, and has been. What a ruling used to say is worth keeping only
where the reasoning stops a rejected design being re-proposed from scratch, and
that has already happened here — 104 and 105 were made on the same day.

**To add a ruling:** append its body to `detail/decisions.md` **and** one row
here. Neither half is optional; an earlier version of this index silently
omitted rulings 102 and 103 for a day. That is now enforced —
`packages/at_client/test/acceptance/docs_structure_test.dart` fails when a row
has no body, when a body has no row, and when a body is written into this
file.

## Status vocabulary

| Status              | Means                                                                                                            |
|---------------------|------------------------------------------------------------------------------------------------------------------|
| `LIVE`              | Stands as ruled.                                                                                                 |
| `AMENDED`           | Stands, but one or more sub-rulings were changed later, on the date given.                                       |
| `PARTLY SUPERSEDED` | Part was replaced and the rest holds, so the title is not struck. The body says which part went.                 |
| `SUPERSEDED`        | Replaced outright. Title struck.                                                                                 |
| `REJECTED`          | Considered and not adopted. Title struck. The body stays so it is not re-proposed from scratch.                  |

The ledger is long because the project made many decisions that still stand,
not because it is full of dead ones — the Status column says which, and it is
the only place that says so. A sentence here counting them was **deleted
2026-08-16**: it said "three" while the table said six, in the very commit that
created both. Two copies of one fact disagree eventually; only one is kept.

⚠️ **Two rulings were both numbered 68.** The second, *Workstream B(ii)*, is
now **68b** — nothing cited it. All eight citations of "decisions 68" mean the
first, `enroll:updateMetadata`, and they still resolve.

**Scope, conventions, and how this ledger relates to its sibling docs** are in
[section 0](detail/decisions.md#0-scope--how-to-read-this-doc).

## The rulings

| #     | Ruling                                                                                      | Date       | Status                    |
|-------|---------------------------------------------------------------------------------------------|------------|---------------------------|
| [1]   | ~~ADR 0001 — D1 as two tiers~~                                                              | 2026-06-20 | SUPERSEDED by [2]         |
| [2]   | ADR 0002 — D1 is single-tier nskey; at/pqmls is D2                                          | 2026-06-25 | LIVE                      |
| [3]   | The OQ1–9 ratified design-decisions table                                                   | —          | LIVE                      |
| [4]   | The verb-wire-shape & 1:1:1 cardinality rulings                                             | —          | LIVE                      |
| [5]   | Retrofit ruling — fresh, self-spawned, auto-approved enrollment                             | —          | LIVE                      |
| [6]   | Resolved & open execution decisions (#A–#F)                                                 | —          | LIVE                      |
| [7]   | Decision log / timeline (dated)                                                             | —          | LIVE                      |
| [8]   | Stale-source reconciliation note                                                            | —          | LIVE                      |
| [9]   | APKAM keypair as key package: considered and rejected                                       | 2026-06-30 | LIVE                      |
| [10]  | nskey derivation from a shared master seed: rejected                                        | 2026-06-30 | LIVE                      |
| [11]  | Single nskey per namespace, lazily published                                                | 2026-06-30 | PARTLY SUPERSEDED by [13] |
| [12]  | Advertised recipient keys are signed against `_apsk`                                        | 2026-07-02 | LIVE                      |
| [13]  | The nskey is published eagerly, mutable, and generation-addressed                           | 2026-08-02 | AMENDED 2026-08-02        |
| [14]  | Content keys are scoped per recipient                                                       | 2026-08-02 | LIVE                      |
| [15]  | The record owner and the nskey owner are different atSigns                                  | 2026-08-02 | LIVE                      |
| [16]  | A provider id names every algorithm a reader needs code for                                 | 2026-08-02 | LIVE                      |
| [17]  | The sync push dropped `appMetadata`                                                         | 2026-08-02 | LIVE                      |
| [18]  | `pqpublickey` becomes the user-owned signing root                                           | 2026-08-03 | AMENDED 2026-08-15        |
| [19]  | Nested namespaces: the nskey is resolved by walking up                                      | 2026-08-03 | LIVE                      |
| [20]  | SS-2: how the key package reaches an enrollment, and how conveyance fires                   | 2026-08-03 | LIVE                      |
| [21]  | SS-3: where key material lives, and what the substrate stops storing                        | 2026-08-03 | LIVE                      |
| [22]  | SS-4: when a namespace key is minted, and what must be true first                           | 2026-08-03 | LIVE                      |
| [23]  | UC-A2.1: reversing the enrollment key exchange                                              | 2026-08-04 | LIVE                      |
| [24]  | How the approval chain terminates at the root                                               | 2026-08-04 | LIVE                      |
| [25]  | The substrate's arrival path had never run                                                  | 2026-08-04 | LIVE                      |
| [26]  | UC-A4.4: a conveyance that loses the race to its own announcement                           | 2026-08-04 | LIVE                      |
| [27]  | The era default: read the new scheme everywhere, write it once                              | 2026-08-04 | LIVE                      |
| [28]  | The PQ performance budget, measured                                                         | 2026-08-04 | LIVE                      |
| [29]  | UC-A3.2 describes a mint trigger that was never built                                       | 2026-08-04 | LIVE                      |
| [30]  | UC-B5.1's pull backstop has no initiator                                                    | 2026-08-04 | LIVE                      |
| [31]  | The root-pull initiator, and what it did not settle                                         | 2026-08-04 | LIVE                      |
| [32]  | The two-enrollment fixture: what works and what does not                                    | 2026-08-04 | LIVE                      |
| [33]  | Keying the client cache by (atSign, enrollmentId)                                           | 2026-08-04 | LIVE                      |
| [34]  | PKAM is record-authoritative, and the no-RSA row reads narrower than it looks               | 2026-08-04 | LIVE                      |
| [35]  | The owed-a-test backlog reached zero                                                        | 2026-08-04 | LIVE                      |
| [36]  | The rollout is the app's decision: capability markers built, examined, and removed          | 2026-08-05 | LIVE                      |
| [37]  | Legacy key material is retained until the ecosystem is PQ, not the atSign                   | 2026-08-05 | LIVE                      |
| [38]  | Key material self-heals: mint-if-absent, else pull                                          | 2026-08-05 | LIVE                      |
| [39]  | `_apsk` rides the same two-stage ladder                                                     | 2026-08-05 | LIVE                      |
| [40]  | RF-SRV is the mechanism the whole model stands on                                           | 2026-08-05 | LIVE                      |
| [41]  | The to-define list                                                                          | 2026-08-05 | LIVE                      |
| [42]  | The to-define list, ruled                                                                   | 2026-08-05 | AMENDED 2026-08-12        |
| [43]  | RF-2b lands, and what the first genuine ML-DSA PKAM found                                   | 2026-08-05 | LIVE                      |
| [44]  | RF-2c: the switch-over, and what it cost to make a client PQ                                | 2026-08-05 | LIVE                      |
| [45]  | The retrofit rows, and the five defects the first end-to-end run found                      | 2026-08-05 | AMENDED 2026-08-15        |
| [46]  | RFC 9180, and where the design's version hatches are                                        | 2026-08-05 | PARTLY SUPERSEDED by [48] |
| [47]  | B-2 lands: two levers, and the difference between excluding and revoking                    | 2026-08-06 | LIVE                      |
| [48]  | The standards question reopened, and what the check found                                   | 2026-08-06 | LIVE                      |
| [49]  | Two KEMs by configuration, and the downgrade gap that stays open                            | 2026-08-06 | LIVE                      |
| [50]  | Two KEMs by configuration, one construction by negotiation                                  | 2026-08-07 | LIVE                      |
| [51]  | The `from:` challenge and a signed envelope must never share a shape                        | 2026-08-08 | LIVE                      |
| [52]  | ON-1: a greenfield atSign starts where a retrofit ends                                      | 2026-08-08 | LIVE                      |
| [53]  | UC-B4.2, and what asking for no legacy material actually costs                              | 2026-08-08 | LIVE                      |
| [54]  | S-3: the two things an updatable key store turned out to be                                 | 2026-08-08 | LIVE                      |
| [55]  | ON-1's consumer half: what "the CLI can do it too" actually cost                            | 2026-08-08 | LIVE                      |
| [56]  | The "make it right" quality pass, and the design goals it settled                           | 2026-08-09 | AMENDED 2026-08-13        |
| [57]  | The wire vocabulary gets one home per family                                                | 2026-08-09 | LIVE                      |
| [58]  | The two published-API breaks are repaired in place                                          | 2026-08-09 | LIVE                      |
| [59]  | Phase-3 at_chops surface rulings                                                            | 2026-08-09 | LIVE                      |
| [60]  | JWS stage one lands: readers always-on, producer behind the version flag                    | 2026-08-09 | LIVE                      |
| [61]  | The barrel cycle is cut: no src file imports a public barrel                                | 2026-08-10 | LIVE                      |
| [62]  | PqClientBootstrap: one owner for the PQ startup                                             | 2026-08-10 | LIVE                      |
| [63]  | Phase 4e: EnrollmentConveyance out of EnrollmentServiceImpl                                 | 2026-08-10 | LIVE                      |
| [64]  | Phase 4f: one CryptoRuntime.prepareWrite()                                                  | 2026-08-10 | LIVE                      |
| [65]  | Phase 4g: the secret-sharing seam work                                                      | 2026-08-10 | LIVE                      |
| [66]  | The approval list's last hop tells the truth                                                | 2026-08-10 | LIVE                      |
| [67]  | Workstream B(i): the sweep anchors to the root                                              | 2026-08-10 | LIVE                      |
| [68]  | The enrollment record stops being a one-way door: `enroll:updateMetadata`                   | 2026-08-10 | AMENDED 2026-08-13        |
| [68b] | Workstream B(ii): approvals anchor to the root                                              | 2026-08-10 | LIVE                      |
| [69]  | Workstream B(iii): the retrofit selector, and the KEM the retrofit froze wrong              | 2026-08-10 | AMENDED 2026-08-13        |
| [70]  | Workstream A capstone: ReleasePosture, the five flags as one value                          | 2026-08-10 | AMENDED 2026-08-13        |
| [71]  | Phase 5 begins: the CLI's handshake copy is deleted                                         | 2026-08-10 | LIVE                      |
| [72]  | Phase 5: the keyfile store's double stops lying, and the lock's three races close           | 2026-08-10 | LIVE                      |
| [73]  | Phase 5: `AtEnrollmentImpl` splits into submitter, approver, handshake                      | 2026-08-10 | LIVE                      |
| [74]  | Phase 5: enrollment material gets one filing path                                           | 2026-08-10 | LIVE                      |
| [75]  | Phase 5: the enrolment request's mode is a constructor, not a field                         | 2026-08-10 | LIVE                      |
| [76]  | The nskey advertises one KEM key, and §50's premise is a release property                   | 2026-08-10 | LIVE                      |
| [77]  | Phase 5: the CLI stops hand-building its keyfile                                            | 2026-08-10 | LIVE                      |
| [78]  | Phase 5: the keychain is reachable, flushable, and no longer closes someone else's service  | 2026-08-10 | LIVE                      |
| [79]  | Phase 6: `maxRetries` becomes a budget for the thing it is named after                      | 2026-08-10 | LIVE                      |
| [80]  | Phase 6: one set of enrollment defaults, and the divergence that never was                  | 2026-08-10 | LIVE                      |
| [81]  | Phase 6: the key-exchange mode is wired, and there is nothing left to wire it to            | 2026-08-10 | LIVE                      |
| [82]  | Phase 7: an approval finishes its own bookkeeping, and every decision closes its connection | 2026-08-11 | LIVE                      |
| [83]  | Phase 7: one home for the shared mocks, and the four families that could not move           | 2026-08-11 | LIVE                      |
| [84]  | Phase 7: the functional pack's live tests stop claiming to be the e2e pack                  | 2026-08-11 | LIVE                      |
| [85]  | Phase 7: the ledger's own index, and what the citation audit measured                       | 2026-08-11 | LIVE                      |
| [86]  | Phase 7: the acceptance ledger reads a declaration instead of inferring one                 | 2026-08-11 | LIVE                      |
| [87]  | Phase 7: the revocation row stops tolerating what it exists to forbid                       | 2026-08-11 | LIVE                      |
| [88]  | Phase 7: mintAndPublish is the cold-start mint, and stops calling itself the rotation       | 2026-08-11 | LIVE                      |
| [89]  | Phase 7: the section symbol keeps the two jobs it is good at                                | 2026-08-11 | LIVE                      |
| [90]  | Phase 7: a refusal the approval wait cannot resolve stops being silent                      | 2026-08-11 | LIVE                      |
| [91]  | Signature agility: the APKAM auth key stops being the enrollment's signing key              | 2026-08-11 | AMENDED 2026-08-18        |
| [92]  | The spike takes trunk, and two published version numbers move underneath it                 | 2026-08-11 | LIVE                      |
| [93]  | The D1 remaining-work sequence, and the rollout axis becomes real                           | 2026-08-11 | AMENDED 2026-08-15        |
| [94]  | Three records advertise keys, and only one of them speaks the vocabulary                    | 2026-08-11 | AMENDED 2026-08-12        |
| [95]  | The envelope keeps one shape, and a retained key says so                                    | 2026-08-12 | AMENDED 2026-08-14        |
| [96]  | The programme pair gets a home outside the workspace                                        | 2026-08-14 | LIVE                      |
| [97]  | A keyfile status a build has never seen is read, not refused                                | 2026-08-14 | LIVE                      |
| [98]  | Rollout 1 moves the authentication key, not the signing key                                 | 2026-08-14 | AMENDED 2026-08-14        |
| [99]  | The keyfile groups by enrollment, and the atSign's own keys move out                        | 2026-08-14 | LIVE                      |
| [100] | The seven shapes ruling 99 left open                                                        | 2026-08-14 | LIVE                      |
| [101] | The signing root becomes an ordinary signing key, and rotatable                             | 2026-08-15 | LIVE                      |
| [102] | An `_apsk` fallback value never replaces a real advertisement                               | 2026-08-15 | AMENDED 2026-08-17        |
| [103] | An envelope says what it is for, and a verifier says what it wants                          | 2026-08-15 | LIVE                      |
| [104] | ~~Per-generation nskey records~~                                                            | 2026-08-16 | REJECTED — see [105]      |
| [105] | The nskey mint elects a winner                                                              | 2026-08-16 | LIVE                      |
| [106] | A notification that outruns its key is dropped, not parked                                  | 2026-08-16 | AMENDED 2026-08-17        |
| [107] | A `local:` record is not encrypted, and the legacy refusal exempts it                       | 2026-08-17 | AMENDED 2026-08-17        |
| [108] | The signing rollout swaps algorithms; it never overlaps them                                | 2026-08-18 | LIVE                      |
| [109] | at_chops 3.6.0 stays a minor; no major bump for this release                                | 2026-08-18 | LIVE                      |
| [110] | The `0x01` seal version is retired; stop emitting before removing                           | 2026-08-18 | LIVE                      |

[1]: detail/decisions.md#1-adr-0001--d1-as-two-tiers-superseded
[2]: detail/decisions.md#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted
[3]: detail/decisions.md#3-the-oq19-ratified-design-decisions-table
[4]: detail/decisions.md#4-the-verb-wire-shape--111-cardinality-rulings
[5]: detail/decisions.md#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment
[6]: detail/decisions.md#6-resolved--open-execution-decisions-af
[7]: detail/decisions.md#7-decision-log--timeline-dated
[8]: detail/decisions.md#8-stale-source-reconciliation-note
[9]: detail/decisions.md#9-apkam-keypair-as-key-package-considered-and-rejected-2026-06-30
[10]: detail/decisions.md#10-nskey-derivation-from-a-shared-master-seed-rejected-2026-06-30
[11]: detail/decisions.md#11-single-nskey-per-namespace-lazily-published-2026-06-30
[12]: detail/decisions.md#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02
[13]: detail/decisions.md#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02
[14]: detail/decisions.md#14-content-keys-are-scoped-per-recipient-2026-08-02
[15]: detail/decisions.md#15-the-record-owner-and-the-nskey-owner-are-different-atsigns-2026-08-02
[16]: detail/decisions.md#16-a-provider-id-names-every-algorithm-a-reader-needs-code-for-2026-08-02
[17]: detail/decisions.md#17-the-sync-push-dropped-appmetadata-2026-08-02-fixed
[18]: detail/decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03
[19]: detail/decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03
[20]: detail/decisions.md#20-ss-2-how-the-key-package-reaches-an-enrollment-and-how-conveyance-fires-2026-08-03
[21]: detail/decisions.md#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03
[22]: detail/decisions.md#22-ss-4-when-a-namespace-key-is-minted-and-what-must-be-true-first-2026-08-03
[23]: detail/decisions.md#23-uc-a21-reversing-the-enrollment-key-exchange-2026-08-04
[24]: detail/decisions.md#24-how-the-approval-chain-terminates-at-the-root-2026-08-04
[25]: detail/decisions.md#25-the-substrates-arrival-path-had-never-run-2026-08-04
[26]: detail/decisions.md#26-uc-a44-a-conveyance-that-loses-the-race-to-its-own-announcement-2026-08-04
[27]: detail/decisions.md#27-the-era-default-read-the-new-scheme-everywhere-write-it-once-2026-08-04
[28]: detail/decisions.md#28-the-pq-performance-budget-measured-2026-08-04
[29]: detail/decisions.md#29-uc-a32-describes-a-mint-trigger-that-was-never-built-2026-08-04
[30]: detail/decisions.md#30-uc-b51s-pull-backstop-has-no-initiator-2026-08-04
[31]: detail/decisions.md#31-the-root-pull-initiator-and-what-it-did-not-settle-2026-08-04
[32]: detail/decisions.md#32-the-two-enrollment-fixture-what-works-and-what-does-not-2026-08-04
[33]: detail/decisions.md#33-keying-the-client-cache-by-atsign-enrollmentid-2026-08-04
[34]: detail/decisions.md#34-pkam-is-record-authoritative-and-the-no-rsa-row-reads-narrower-than-it-looks-2026-08-04
[35]: detail/decisions.md#35-the-owed-a-test-backlog-reached-zero-2026-08-04
[36]: detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05
[37]: detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05
[38]: detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05
[39]: detail/decisions.md#39-_apsk-rides-the-same-two-stage-ladder-2026-08-05
[40]: detail/decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05
[41]: detail/decisions.md#41-the-to-define-list-2026-08-05
[42]: detail/decisions.md#42-the-to-define-list-ruled-2026-08-05
[43]: detail/decisions.md#43-rf-2b-lands-and-what-the-first-genuine-ml-dsa-pkam-found-2026-08-05
[44]: detail/decisions.md#44-rf-2c-the-switch-over-and-what-it-cost-to-make-a-client-pq-2026-08-05
[45]: detail/decisions.md#45-the-retrofit-rows-and-the-five-defects-the-first-end-to-end-run-found-2026-08-05
[46]: detail/decisions.md#46-rfc-9180-and-where-the-designs-version-hatches-are-2026-08-05
[47]: detail/decisions.md#47-b-2-lands-two-levers-and-the-difference-between-excluding-and-revoking-2026-08-06
[48]: detail/decisions.md#48-the-standards-question-reopened-and-what-the-check-found-2026-08-06
[49]: detail/decisions.md#49-two-kems-by-configuration-and-the-downgrade-gap-that-stays-open-2026-08-06
[50]: detail/decisions.md#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07
[51]: detail/decisions.md#51-the-from-challenge-and-a-signed-envelope-must-never-share-a-shape-2026-08-08
[52]: detail/decisions.md#52-on-1-a-greenfield-atsign-starts-where-a-retrofit-ends-2026-08-08
[53]: detail/decisions.md#53-uc-b42-and-what-asking-for-no-legacy-material-actually-costs-2026-08-08
[54]: detail/decisions.md#54-s-3-the-two-things-an-updatable-key-store-turned-out-to-be-2026-08-08
[55]: detail/decisions.md#55-on-1s-consumer-half-what-the-cli-can-do-it-too-actually-cost-2026-08-08
[56]: detail/decisions.md#56-the-make-it-right-quality-pass-and-the-design-goals-it-settled-2026-08-09
[57]: detail/decisions.md#57-the-wire-vocabulary-gets-one-home-per-family-2026-08-09
[58]: detail/decisions.md#58-the-two-published-api-breaks-are-repaired-in-place-2026-08-09
[59]: detail/decisions.md#59-phase-3-at_chops-surface-rulings-2026-08-09
[60]: detail/decisions.md#60-jws-stage-one-lands-readers-always-on-producer-behind-the-version-flag-2026-08-09
[61]: detail/decisions.md#61-the-barrel-cycle-is-cut-no-src-file-imports-a-public-barrel-2026-08-10
[62]: detail/decisions.md#62-pqclientbootstrap-one-owner-for-the-pq-startup-2026-08-10
[63]: detail/decisions.md#63-phase-4e-enrollmentconveyance-out-of-enrollmentserviceimpl-2026-08-10
[64]: detail/decisions.md#64-phase-4f-one-cryptoruntimepreparewrite-2026-08-10
[65]: detail/decisions.md#65-phase-4g-the-secret-sharing-seam-work-2026-08-10
[66]: detail/decisions.md#66-the-approval-lists-last-hop-tells-the-truth-2026-08-10
[67]: detail/decisions.md#67-workstream-bi-the-sweep-anchors-to-the-root-2026-08-10
[68]: detail/decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10
[68b]: detail/decisions.md#68b-workstream-bii-approvals-anchor-to-the-root-2026-08-10
[69]: detail/decisions.md#69-workstream-biii-the-retrofit-selector-and-the-kem-the-retrofit-froze-wrong-2026-08-10
[70]: detail/decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10
[71]: detail/decisions.md#71-phase-5-begins-the-clis-handshake-copy-is-deleted-2026-08-10
[72]: detail/decisions.md#72-phase-5-the-keyfile-stores-double-stops-lying-and-the-locks-three-races-close-2026-08-10
[73]: detail/decisions.md#73-phase-5-atenrollmentimpl-splits-into-submitter-approver-handshake-2026-08-10
[74]: detail/decisions.md#74-phase-5-enrollment-material-gets-one-filing-path-2026-08-10
[75]: detail/decisions.md#75-phase-5-the-enrolment-requests-mode-is-a-constructor-not-a-field-2026-08-10
[76]: detail/decisions.md#76-the-nskey-advertises-one-kem-key-2026-08-10
[77]: detail/decisions.md#77-phase-5-the-cli-stops-hand-building-its-keyfile-2026-08-10
[78]: detail/decisions.md#78-phase-5-the-keychain-is-reachable-flushable-and-no-longer-closes-someone-elses-service-2026-08-10
[79]: detail/decisions.md#79-phase-6-maxretries-becomes-a-budget-for-the-thing-it-is-named-after-2026-08-10
[80]: detail/decisions.md#80-phase-6-one-set-of-enrollment-defaults-and-the-divergence-that-never-was-2026-08-10
[81]: detail/decisions.md#81-phase-6-the-key-exchange-mode-is-wired-and-there-is-nothing-left-to-wire-it-to-2026-08-10
[82]: detail/decisions.md#82-phase-7-an-approval-finishes-its-own-bookkeeping-and-every-decision-closes-its-connection-2026-08-11
[83]: detail/decisions.md#83-phase-7-one-home-for-the-shared-mocks-and-the-four-families-that-could-not-move-2026-08-11
[84]: detail/decisions.md#84-phase-7-the-functional-packs-live-tests-stop-claiming-to-be-the-e2e-pack-2026-08-11
[85]: detail/decisions.md#85-phase-7-the-ledgers-own-index-and-what-the-citation-audit-measured-2026-08-11
[86]: detail/decisions.md#86-phase-7-the-acceptance-ledger-reads-a-declaration-instead-of-inferring-one-2026-08-11
[87]: detail/decisions.md#87-phase-7-the-revocation-row-stops-tolerating-what-it-exists-to-forbid-2026-08-11
[88]: detail/decisions.md#88-phase-7-mintandpublish-is-the-cold-start-mint-and-stops-calling-itself-the-rotation-2026-08-11
[89]: detail/decisions.md#89-phase-7-the-section-symbol-keeps-the-two-jobs-it-is-good-at-2026-08-11
[90]: detail/decisions.md#90-phase-7-a-refusal-the-approval-wait-cannot-resolve-stops-being-silent-2026-08-11
[91]: detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11
[92]: detail/decisions.md#92-the-spike-takes-trunk-and-two-published-version-numbers-move-underneath-it-2026-08-11
[93]: detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11
[94]: detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11
[95]: detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12
[96]: detail/decisions.md#96-the-programme-pair-gets-a-home-outside-the-workspace-2026-08-14
[97]: detail/decisions.md#97-a-keyfile-status-a-build-has-never-seen-is-read-not-refused-2026-08-14
[98]: detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14
[99]: detail/decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14
[100]: detail/decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14
[101]: detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15
[102]: detail/decisions.md#102-an-_apsk-fallback-value-never-replaces-a-real-advertisement-2026-08-15
[103]: detail/decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15
[104]: detail/decisions.md#104-per-generation-nskey-records-rejected-2026-08-16
[105]: detail/decisions.md#105-the-nskey-mint-elects-a-winner-2026-08-16
[106]: detail/decisions.md#106-a-notification-that-outruns-its-key-is-dropped-not-parked-2026-08-16
[107]: detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17
[108]: detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18
[109]: detail/decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18
[110]: detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18
