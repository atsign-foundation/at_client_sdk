/// Blockers for the D1 acceptance burn-down.
///
/// Each constant names the project from
/// `docs/projects/pq/implementation-plan.md` that must land before the scenarios
/// it guards can go green, plus the test layer the finished assertion belongs
/// in. Grep a constant to see everything a single project unblocks — that is the
/// point of naming them.
///
/// A constant names a scenario's **first** gate. A project that is a later gate
/// on an already-blocked row — RF-2c's e2e orchestration behind RF-SRV, RF-2b
/// and R-1 on the B clusters — owns no constant, because it cannot unblock
/// anything on its own.
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

const _unit = 'layer: at_client dart test';
const _functional = 'layer: tests/at_functional_test runLocal.sh';
const _e2e = 'layer: tests/at_end2end_test';

// ---------------------------------------------------------------------------
// Critical path to D1 GA
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Owed a test, not a project (2026-08-04)
// ---------------------------------------------------------------------------
//
// SS-2, SS-4 and B-1 have landed. Their scenarios are therefore no longer
// *blocked* — nobody is waiting on code — but most are not yet *proven*, and
// conflating those two states is what made this burn-down misleading in the
// first place. A row reading `blocked: B-1` said "the project owes this";
// these say "we owe this a test", which is a different backlog with a
// different owner.
//
// A row whose proof already exists in another package should cite it with
// `provenIn` (see `proven_elsewhere.dart`) instead of carrying one of these.

/// The project landed; this scenario still needs writing, as a unit test.
const owedUnit = 'owed: scenario not yet written · $_unit';

/// The project landed; this scenario still needs writing, live.
const owedFunctional = 'owed: scenario not yet written · $_functional';

/// The project landed; this scenario still needs writing, cross-atSign.
const owedE2e = 'owed: scenario not yet written · $_e2e';

/// The initiator now exists; the live round trip is still unproven.
///
/// `PqSigningRoot.requestPrivateIfAbsent` is wired into client start and its
/// three guards are unit-covered, so this is no longer "nothing initiates it".
/// What is missing is a fixture with two real APKAM enrollments: the
/// functional harness authenticates with the atSign's own keys, so the
/// enumeration is refused with "enroll:listns requires APKAM authentication",
/// and addressing a holder directly puts the envelope on the atServer but
/// produces no answer — for reasons not yet established, and deliberately not
/// guessed at.
/// See [decisions 31](../../../../docs/projects/pq/decisions.md).
const rootPullNotBuilt =
    'blocked: the signing-root pull round trip is unproven · $_functional';

/// Migration machinery + disallowLegacyEncryption flag.
const r1 = 'blocked: R-1 (scheme negotiation + flag) · $_unit';
const r1CrossAtSign = 'blocked: R-1 (scheme negotiation + flag) · $_e2e';

/// The two rotation levers + revocation composition.
const b2 = 'blocked: B-2 (nskey rotation + revocation) · $_functional';

// ---------------------------------------------------------------------------
// Off the critical path — retrofit, onboarding
// ---------------------------------------------------------------------------

/// atServer authenticated self-retrofit enroll (auto-approve + expiry cap).
const rfSrv = 'blocked: RF-SRV (server self-retrofit enroll) · $_e2e';

/// Client mints PQ APKAM + key package, then self-retrofits.
const rf2b = 'blocked: RF-2b (PQ-APKAM mint + self-retrofit) · $_e2e';

/// PQ-native greenfield onboarding + legacy-interop flag.
const on1 = 'blocked: ON-1 (PQ-native onboarding) · $_functional';
const on1CrossAtSign = 'blocked: ON-1 (PQ-native onboarding) · $_e2e';
