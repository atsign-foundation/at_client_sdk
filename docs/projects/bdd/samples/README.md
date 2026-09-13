# Sample translations

Eleven rows of [`docs/projects/pq/acceptance.md`](../../pq/acceptance.md) translated
by hand into Gherkin on 2026-09-02, to find out where the catalogue's shape fits the
format and where it does not. Nothing runs them, and they are not the catalogue: the
rows they were drawn from remain the authority until a runner exists and a row is
moved deliberately. What each translation kept, split, merged or dropped, and the
friction it exposed, is in [`analysis.md` section 6](../analysis.md#6-the-translation-sample).

The rows were chosen to cover every shape the catalogue uses, one file per row:

| File | Row | Why it was picked |
|---|---|---|
| `a1_onboard.feature` | UC-A1.1 | the plain `- **Then:**` bullet form with six sub-bullets, a `Steps` list and a state table |
| `a2_enrollment.feature` | UC-A2.1 | a `Steps` list that is design rather than test steps; request and approval fused in one helper |
| `a3_self_data.feature` | UC-A3.3 | the row's primary assertion is the Then's headline, which the clause parser drops |
| `a5_rotation.feature` | UC-A5.1 | the one row the suite splits into `(a)` and `(b)`; a 691-character clause carrying seven observables |
| `b5_edge_cases.feature` | UC-B5.6 | the atServer-side interlock that only a live run can find |
| `c1_rollout_withdrawn.feature` | UC-C1.3 | the withdrawn row: how a step-less scenario keeps the id addressable |
| `g1_keyfile.feature` | UC-G1.2 | the italic `*Then*` style, three assertions joined by semicolons in one clause |
| `g1_wire.feature` | UC-G1.7 | an assertion with its control arm, plus two assertions that live in a coverage paragraph rather than a clause |
| `g2_agility.feature` | UC-G2.9 | the one unprovable clause, and a row that is mostly analysis |
| `g3_data_signing_key.feature` | UC-G3.10 | a refusal whose observable is the state the atServer is left in |
| `cross_cutting_invariant.feature` | section 13, `appMetadata.providerId` is authoritative | an unnumbered invariant, outside the 232 clauses by design |

Tags are the scheme proposed in the analysis: `@UC-<id>` for traceability, one of
`@live`, `@in-process`, `@live-exempt`, `@live-owed`, `@unprovable`, `@withdrawn` for
the proof level (a claim for the ledger to check, never a fact for it to believe),
and the domain tags from Gary's aupoqua conventions (`@happy`, `@negative`,
`@security`, `@adversarial`, `@limitation`, `@assumption`) plus `@control`. Several
files are scenario fragments rather than whole Features, because the sample took
one row from the middle of a section; the runner design in
[`design.md`](../design.md) says how a whole section becomes one Feature.
