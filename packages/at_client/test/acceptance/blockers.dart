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
/// A constant can outlive the thing it names: re-read it before believing a row
/// is still blocked, and check that the named layer's pack can actually run the
/// assertion before recording that layer.
///
/// `blocked:` and `owed:` are different states — a project that has landed
/// leaves its rows *owed a test*, not blocked.
///
/// Declaring nothing is a valid state for this file; it stays so the next
/// blocker has somewhere to go. To block a row: add a `const` here naming the
/// project and the layer, and `skip:` the scenario against it.
/// `catalogue_test.dart` enforces both directions — a `skip:` with nothing
/// declaring it, and a constant guarding nothing, are each a failure.
library;
