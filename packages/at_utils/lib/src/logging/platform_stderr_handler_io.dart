import 'package:at_utils/src/logging/handlers.dart';
import 'package:at_utils/src/logging/io_handlers.dart';

/// The handler `AtSignLogger.stdErrLoggingHandler` holds where there is a
/// stderr.
LoggingHandler platformStdErrHandler() => StdErrLoggingHandler();
