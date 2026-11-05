import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;

/// The handler the RPC client's logger binds where there is no stderr:
/// `AtSignLogger`'s default.
LoggingHandler rpcLoggingHandler() => AtSignLogger.defaultLoggingHandler;
