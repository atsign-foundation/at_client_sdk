/// What a released at_client is asked to do, so that it can be asked from a
/// separate process.
///
/// No single process can hold two versions of at_client, and the only
/// authority on what a **deployed** peer makes of an enrollment's
/// advertisement is a deployed peer — so the reader below is written once and
/// compiled against the hosted 3.14.0 by `tests/pq_matrix/published`.
library;

export 'src/apsk_reader.dart';
export 'src/connect.dart';
