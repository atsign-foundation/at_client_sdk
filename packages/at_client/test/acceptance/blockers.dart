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

// Every layer's constant is gone, one project at a time. `at_client dart test`
// went first (every unit-layer scenario is written), then the functional layer
// (ON-1 was the last to block one, and UC-A1.1 cites its live test), and now
// the e2e layer with `rfSrv` below. The next project to block a row declares
// its own constant here, with the layer the finished assertion belongs in:
//
//   const _e2e = 'layer: tests/at_end2end_test';
//   const someProject = 'blocked: SOME-1 (what it is) · $_e2e';

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

// ---------------------------------------------------------------------------
// Nothing is blocked any more.
//
// This file is deliberately kept rather than deleted. Its job is to make a
// project's unfinished scenarios greppable — `catalogue_test.dart` fails if a
// constant here guards nothing, so a stale one cannot sit unnoticed, and the
// next project that blocks a row declares its constant here with the layer the
// finished assertion belongs in.
//
// The last one to go was `rfSrv`, which guarded UC-B0.1. It had outlived its
// own accuracy: RF-SRV's server half landed 2026-08-05, and what actually
// blocked the row from then on was the HARNESS — it needs an atServer WITHOUT
// the retrofit verbs to abort against, and no image here provided one. That
// stopped being true when `atsigncompany/virtualenv:vip-p3.15.0` was published:
// a release-pinned tag stays pre-PQ for good, so the row is now proven against
// it (tests/at_end2end_test/test/pq/legacy_server_abort_test.dart, tagged
// `legacy-server`). The lesson worth keeping is that a blocker naming a
// PROJECT can go on being cited long after the project lands, because nobody
// re-reads it — see decisions.md 53.1 for the same mistake about a test layer.
// ---------------------------------------------------------------------------
// ON-1 is fully discharged. Its cross-atSign row, UC-B4.2, was labelled
// `blocked: ON-1 · layer: tests/at_end2end_test` on the reasoning that only an
// e2e run with two atSigns could show the inbound direction. The layer was
// wrong, and the reason is worth keeping: `tests/at_end2end_test` runs in CI
// against long-lived cicd atSigns, so it can never CRAM-activate anything,
// and its `TestSuiteInitializer` dereferences `apkamPublicKey!` — null in
// every PQ-native keyfile. `tests/at_functional_test` runs against the
// virtualenv container in CI as well as locally, already holds UC-A1.1, and
// drives two atSigns in one file perfectly well. The row is proven there.
