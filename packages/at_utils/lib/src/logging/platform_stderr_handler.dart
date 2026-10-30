import 'package:at_utils/src/logging/handlers.dart';

/// The handler `AtSignLogger.stdErrLoggingHandler` holds where there is no
/// stderr: the console.
LoggingHandler platformStdErrHandler() => ConsoleLoggingHandler();
