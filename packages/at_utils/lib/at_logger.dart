/// at_utils' logging surface — [AtSignLogger] and its handlers.
///
/// This barrel names no `dart:io` type, so it is safe to import from a
/// web/WASM build graph. That matters because `at_chops`, `at_auth`,
/// `at_lookup` and `at_client` all import it, and until at_utils 3.5.0 it was
/// the path by which `dart:io` reached every one of them.
///
/// `FileLoggingHandler`, `StdErrLoggingHandler` and `CLILoggingHandler` are
/// still exported here on **every** platform: native builds get the `dart:io`
/// implementations, web builds get console-backed stand-ins that warn once on
/// first use. Nothing that names them needs to change per platform.
///
/// New code writing a CLI should import `package:at_utils/at_utils_cli.dart`
/// for `CLILoggingHandler` — that is its permanent home, and the re-export
/// below goes away in the next major.
library;

export 'package:at_utils/src/logging/atsignlogger.dart';
export 'package:at_utils/src/logging/handlers.dart';
export 'package:at_utils/src/logging/handlers_stub.dart'
    if (dart.library.io) 'package:at_utils/src/logging/handlers_io.dart';

/// Back-compat: `CLILoggingHandler` lived here before 3.5.0. Its real home is
/// `at_utils_cli.dart`; on web this resolves to an uncoloured console stub, so
/// the export cannot drag chalkdart — and `dart:io` — in with it.
export 'package:at_utils/src/logging/cli_stub.dart'
    if (dart.library.io) 'package:at_utils/src/logging/cli.dart'
    show CLILoggingHandler;
