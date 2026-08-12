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
library;

export 'package:at_utils/src/logging/atsignlogger.dart';
export 'package:at_utils/src/logging/handlers.dart';
export 'package:at_utils/src/logging/handlers_stub.dart'
    if (dart.library.io) 'package:at_utils/src/logging/handlers_io.dart';
