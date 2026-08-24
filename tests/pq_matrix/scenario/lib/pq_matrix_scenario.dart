/// What a released at_client is asked to do, so that it can be asked from a
/// separate process.
///
/// This package exists for one reason now: no single process can hold two
/// versions of at_client, and the only authority on what a **deployed** peer
/// makes of an enrollment's advertisement is a deployed peer. So the reader
/// below is written once and compiled against the hosted 3.14.0 by
/// `tests/pq_matrix/published`.
///
/// ⚠️ **It used to be much more than this.** It carried the whole exchange —
/// puts, gets, a notification, a line protocol — because the rollout matrix
/// ran every cell as two processes for the same version reason. That matrix
/// is gone: the posture grid runs in one process in the functional pack, which
/// it can because it no longer has a released arm among its cells. What
/// survives here is the one measurement that genuinely needs a second build.
library;

export 'src/apsk_reader.dart';
export 'src/connect.dart';
