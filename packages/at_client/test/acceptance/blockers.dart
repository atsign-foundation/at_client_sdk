/// Blockers for the D1 acceptance burn-down.
///
/// Each constant names the project from
/// `docs/projects/pq/implementation-plan.md` that must land before the scenarios
/// it guards can go green, plus the test layer the finished assertion belongs
/// in. Grep a constant to see everything a single project unblocks — that is the
/// point of naming them.
///
/// A constant names a scenario's **first** gate, so a project that is only ever
/// a later gate owns none. The layer is part of the constant, because a project
/// whose scenarios land in two suites needs two.
///
/// When a project lands, delete its constant and the analyzer will point at
/// every scenario now owed an implementation. `catalogue_test.dart` fails if a
/// constant guards nothing, so a stale one cannot sit here unnoticed.
///
/// Two lessons from the burn-down that reached zero on 2026-08-08, kept because
/// both cost real time:
///
/// - **A blocker naming a PROJECT goes on being cited long after the project
///   lands**, because nobody re-reads it. `rfSrv` guarded UC-B0.1 for three days
///   after RF-SRV's server half shipped; what actually blocked the row was the
///   harness. Re-read a constant before believing it.
/// - **The layer in the label is a checkable claim about a harness**, not a
///   note. UC-B4.2 sat labelled for `tests/at_end2end_test` for a month; that
///   pack runs in CI against long-lived cicd atSigns and can never CRAM-activate
///   anything. Verify the named pack can do the thing before recording it.
///
/// `blocked:` and `owed:` are different states. A project that has landed leaves
/// its rows *owed a test*, not blocked — conflating them made this burn-down
/// misleading in both directions at once (decisions.md 35).
library;

// ---------------------------------------------------------------------------
// Layers (acceptance.md section 14)
// ---------------------------------------------------------------------------

const _functional = 'layer: tests/at_functional_test';

// ---------------------------------------------------------------------------
// Blocked on a project
// ---------------------------------------------------------------------------

/// UC-A2.5 / UC-A2.6 — `enroll:updateMetadata` and the multi-kpid receiver.
///
/// Both rows need the verb to exist on the atServer and the client to hold more
/// than one KEM keypair; neither half is built (decisions.md 68). The layer is
/// the functional pack rather than e2e for the reason UC-B4.2 established: it
/// runs against the virtualenv container in CI as well as locally, drives more
/// than one enrollment of one atSign in a single file, and can activate an
/// atSign from CRAM — none of which the e2e pack can do.
const ke2 = 'blocked: KE-2 (enroll:updateMetadata + multi-kpid) · $_functional';
