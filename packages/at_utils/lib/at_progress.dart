/// Progress reporting — [ProgressEvent], [ProgressEventType] and
/// [ProgressPublisher].
///
/// This barrel names no `dart:io` type. Before at_utils 3.5.0 it did, via
/// `package:chalkdart`, which meant every consumer of at_auth's
/// `progressStream` inherited `dart:io`.
library;

export 'package:at_utils/src/logging/progress.dart';

/// Back-compat: the `ChalkFunction` extension (`ProgressEventType.chalkFn`)
/// lived here before 3.5.0. Its real home is `at_utils_cli.dart` — colour is a
/// terminal concern — and on web this resolves to an uncoloured pass-through so
/// the export cannot drag chalkdart, and `dart:io`, in with it.
///
/// A CLI should import `at_utils_cli.dart` explicitly; this re-export goes away
/// in the next major.
export 'package:at_utils/src/logging/cli_stub.dart'
    if (dart.library.io) 'package:at_utils/src/logging/cli.dart'
    show ChalkFunction;
