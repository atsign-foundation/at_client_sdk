import 'package:at_utils/at_utils_io.dart'
    show LoggingHandler, StdErrLoggingHandler;

/// The handler the RPC client's logger binds where there is a stderr, which
/// keeps its lines out of what a program writes to stdout.
LoggingHandler rpcLoggingHandler() => StdErrLoggingHandler();
