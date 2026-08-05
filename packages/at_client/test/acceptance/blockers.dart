/// Blockers for the D1 acceptance burn-down.
///
/// Each constant names the project from
/// `docs/projects/pq/implementation-plan.md` that must land before the scenarios
/// it guards can go green, plus the test layer the finished assertion belongs
/// in. Grep a constant to see everything a single project unblocks — that is the
/// point of naming them.
///
/// A constant names a scenario's **first** gate, so a project that is only ever
/// a later gate owns none. That is a moving target: RF-2c's e2e rows sat behind
/// R-1, RF-2b and RF-SRV until all three landed, at which point RF-2c became
/// the first gate and the rows became `owed:` (see below).
///
/// The layer is part of the constant, so a project whose scenarios land in two
/// suites needs two — hence the `CrossAtSign` variants.
///
/// When a project lands, delete its constant and the analyzer will point at
/// every scenario now owed an implementation. `catalogue_test.dart` fails if a
/// constant guards nothing, so a stale one cannot sit here unnoticed.
library;

// ---------------------------------------------------------------------------
// Layers (acceptance.md section 14)
// ---------------------------------------------------------------------------

// `at_client dart test` is not among them any more: every scenario that lands
// in this package's own unit suite is now written, so no constant names that
// layer. The next project to block a unit row adds it back.
const _functional = 'layer: tests/at_functional_test runLocal.sh';
const _e2e = 'layer: tests/at_end2end_test';

// ---------------------------------------------------------------------------
// Owed a test vs blocked on a project — the distinction this file exists for
// ---------------------------------------------------------------------------
//
// SS-2, SS-4 and B-1's 21 scenarios were re-labelled from `blocked: <project>`
// to `owed: <a test>` when those projects landed, because a project landing
// makes its scenarios owed a test rather than proven — and conflating those is
// what made this burn-down misleading in both directions at once.
//
// All 17 have since been discharged: fifteen written or cited, one (UC-A3.2)
// found to be a catalogue error rather than a missing test, and one (UC-B5.1)
// found to need production code that did not exist.
//
// The `owed*` label came back on 2026-08-05: RF-2c's switch-over landed
// (decisions.md 44) leaving only its own acceptance rows outstanding, so those
// rows are owed a test rather than blocked on an unlanded project. Labelling
// them `blocked: RF-2c` would be circular — the project's sole remaining
// deliverable IS the row.
//
// R-1's constants are gone too — first because it landed, then because its
// marker half was REMOVED by the app-decides model (decisions.md 36): the B3
// and cross-cutting rows assert the two-release ladder directly, and the B4
// rows cite the cold-start and data-path live tests.

// --- Critical path to D1 GA ---

/// The two rotation levers + revocation composition.
const b2 = 'blocked: B-2 (nskey rotation + revocation) · $_functional';

// ---------------------------------------------------------------------------
// Retrofit + onboarding. RF-SRV moved ONTO the GA critical path 2026-08-05
// (decisions.md 40) — every migration scenario conjugates "upgrade the
// enrollment", and that verb is RF-SRV's. The server half is spiked
// (at_server branch gkc-pq-rfsrv-spike, wire shape frozen by decisions.md 42
// item 1) and RF-2b's client half landed 2026-08-05 with live coverage
// (tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart:
// no-OTP auto-approve, ML-DSA PKAM under the new id, mint-once, tagged
// _apsk). The B1 rows stay skipped because their THEN clauses also demand
// the signing-root interplay and clone orchestration — RF-2c's e2e, not the
// submit path.
// ---------------------------------------------------------------------------

/// atServer authenticated self-retrofit enroll (auto-approve + expiry cap).
/// On the GA critical path per decisions.md 40.
const rfSrv = 'blocked: RF-SRV (server self-retrofit enroll) · $_e2e';

/// RF-2b landed 2026-08-05 (decisions.md 43) and RF-2c's switch-over with it
/// (decisions.md 44: `selfRetrofit`, the per-enrollment signing algorithm
/// threaded to every connection, enrollment-scoped key-package adoption).
/// What these rows still need is the e2e coverage itself.
const owedB1 = 'owed: the UC-B1.x e2e rows — signing-root in-flow '
    '(privileged mint/convey vs request+verify; a scoped enrollment skips '
    'it), two clones of one pre-PQ keyfile reaching DISTINCT enrollment ids, '
    'and the capped legacy enrollment observed ageing out · $_e2e';

/// PQ-native greenfield onboarding + legacy-interop flag.
const on1 = 'blocked: ON-1 (PQ-native onboarding) · $_functional';
const on1CrossAtSign = 'blocked: ON-1 (PQ-native onboarding) · $_e2e';
