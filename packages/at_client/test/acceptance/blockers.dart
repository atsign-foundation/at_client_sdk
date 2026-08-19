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
/// ⚠️ **This file declares NOTHING today, and that is the correct state.** The
/// burn-down reached zero a second time on 2026-08-19, when KE-2's writer
/// landed and UC-A2.5/UC-A2.6 were cited to
/// `tests/at_functional_test/test/key_package_amendment_live_test.dart`.
///
/// It reached zero once before, on 2026-08-08, and the file was **deleted**
/// then — after which KE-2 blocked two rows and the file had to come back.
/// Kept this time, because the documentation above is what was actually
/// expensive, and because the burn-down demonstrably returns above zero. The
/// layer constants went with the blockers that used them: a layer label with
/// no blocker to attach it to is a spelling nobody can check.
///
/// To block a row again: add a `const` here naming the project and the layer,
/// and `skip:` the scenario against it. `catalogue_test.dart` enforces both
/// directions — a `skip:` with nothing declaring it, and a constant guarding
/// nothing, are each a failure.
library;
