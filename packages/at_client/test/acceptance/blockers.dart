/// Blockers for the D1 acceptance burn-down.
///
/// Each constant names the project from `docs/projects/pq/implementation-plan.md`
/// that must land before the scenarios it guards can go green, plus the test
/// layer the finished assertion belongs in. Grep a constant to see everything a
/// single project unblocks — that is the point of naming them.
///
/// When a project lands, delete its constant and the analyzer will point at
/// every scenario now owed an implementation.
library;

// ---------------------------------------------------------------------------
// Layers (acceptance.md section 14)
// ---------------------------------------------------------------------------

const _unit = 'layer: at_client dart test';
const _functional = 'layer: tests/at_functional_test runLocal.sh';
const _e2e = 'layer: tests/at_end2end_test';
const _vectors = 'layer: at_chops vectors';

// ---------------------------------------------------------------------------
// Critical path to D1 GA
// ---------------------------------------------------------------------------

/// nskey minting + pqpublickey lifecycle. Delivers key *material* only.
const ss4 = 'blocked: SS-4 (nskey mint + pqpublickey lifecycle) · $_functional';

/// The value-level data path — the D1 GA convergence point.
const b1 = 'blocked: B-1 (nskey data path providers) · $_unit';
const b1CrossAtSign = 'blocked: B-1 (nskey data path providers) · $_e2e';

/// Migration machinery + disallowLegacyEncryption flag.
const r1 = 'blocked: R-1 (scheme negotiation + flag) · $_unit';

/// The two rotation levers + revocation composition.
const b2 = 'blocked: B-2 (nskey rotation + revocation) · $_functional';

// ---------------------------------------------------------------------------
// Substrate
// ---------------------------------------------------------------------------

/// Substrate wired into AtClient + server wake-up + key-package-in-request.
const ss2 = 'blocked: SS-2 (substrate wired into AtClient) · $_functional';

// ---------------------------------------------------------------------------
// Off the critical path — retrofit, onboarding
// ---------------------------------------------------------------------------

/// atServer authenticated self-retrofit enroll (auto-approve + expiry cap).
const rfSrv = 'blocked: RF-SRV (server self-retrofit enroll) · $_e2e';

/// Client mints PQ APKAM + key package, then self-retrofits.
const rf2b = 'blocked: RF-2b (PQ-APKAM mint + self-retrofit) · $_e2e';

/// Retrofit orchestration + readiness flip + full e2e.
const rf2c = 'blocked: RF-2c (retrofit orchestration + readiness flip) · $_e2e';

/// PQ-native greenfield onboarding + legacy-interop flag.
const on1 = 'blocked: ON-1 (PQ-native onboarding) · $_functional';

// ---------------------------------------------------------------------------
// Cross-cutting
// ---------------------------------------------------------------------------

/// Primitive-level vectors — the shipped at_chops base.
const vectors = 'blocked: harness not yet written · $_vectors';
