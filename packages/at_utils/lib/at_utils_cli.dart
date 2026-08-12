/// at_utils' terminal-only surface: the pieces that render ANSI colour, and the
/// only place `package:chalkdart` is reachable from.
///
/// Import this **in addition to** `at_logger.dart` / `at_progress.dart` when
/// you are writing a command-line program:
///
/// ```dart
/// import 'package:at_utils/at_logger.dart';
/// import 'package:at_utils/at_utils_cli.dart';
///
/// AtSignLogger.defaultLoggingHandler = CLILoggingHandler();
/// stderr.writeln('${event.type.chalkFn(event.group)} : ${event.msg}');
/// ```
///
/// Everything here assumes a terminal. Do not import it from a library, a
/// Flutter app or a web build: chalkdart names `dart:io` with no web-safe
/// variant, so importing this barrel is what would put `dart:io` back into
/// at_chops, at_auth, at_lookup and at_client.
library;

/// [CLILoggingHandler] — colour-coded log output to stderr.
/// [ChalkFunction] — `ProgressEventType.chalkFn`, for colouring a progress stream.
///
/// The `if (dart.library.io)` here looks redundant for a CLI-only barrel, and it
/// is — for this barrel alone. It exists so this resolves to the *same library*
/// as the back-compat re-exports in `at_logger.dart` and `at_progress.dart`. A
/// CLI imports both this and `at_logger.dart`; if the two disagreed about which
/// library declares `CLILoggingHandler`, every such program would fail to
/// analyse with an ambiguous-import error. Drop the condition when those
/// re-exports go away in the next major.
export 'src/logging/cli_stub.dart' if (dart.library.io) 'src/logging/cli.dart';
