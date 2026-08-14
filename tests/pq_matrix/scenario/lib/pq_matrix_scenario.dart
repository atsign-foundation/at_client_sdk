/// The exchange the rollout matrix drives.
///
/// Written once, against the API surface at_client **3.14.0** and this tree
/// both have, and compiled twice: `tests/pq_matrix/current` resolves at_client
/// by path, `tests/pq_matrix/published` resolves the hosted 3.14.0. Only the
/// preference and the attach step differ between the two arms, and both are
/// arguments this library takes rather than code it contains.
///
/// That is what makes a matrix result attributable. Two hand-written programs
/// differ for two possible reasons — at_client changed, or the programs did —
/// and a matrix cannot tell those apart. One scenario removes the second
/// reason (`docs/projects/pq/decisions.md` 96 ruling 3).
library;

export 'src/connect.dart';
export 'src/entrypoint.dart';
export 'src/exchange.dart';
export 'src/protocol.dart';
