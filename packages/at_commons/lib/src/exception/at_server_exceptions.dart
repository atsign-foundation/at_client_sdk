// ignore_for_file: use_super_parameters

import 'package:at_commons/src/exception/at_exceptions.dart';

class AtServerException extends AtException {
  AtServerException(String message) : super(message);
}

/// Thrown when current server's inbound connection limit is reached
class InboundConnectionLimitException extends AtServerException {
  InboundConnectionLimitException(String message) : super(message);
}

/// Thrown when current server's outbound connection limit is reached
class OutboundConnectionLimitException extends AtServerException {
  OutboundConnectionLimitException(String message) : super(message);
}

class BlockedConnectionException extends AtServerException {
  BlockedConnectionException(String message) : super(message);
}

/// Thrown when lookup fails after handshake
class LookupException extends AtServerException {
  LookupException(String message) : super(message);
}

/// Thrown for any unhandled server exception
class InternalServerException extends AtServerException {
  InternalServerException(String message) : super(message);
}

/// Thrown for any unhandled server error
class InternalServerError extends AtServerException {
  InternalServerError(String message) : super(message);
}

/// Thrown when a request is received on a connection while the server is paused
class ServerIsPausedException extends AtServerException {
  ServerIsPausedException(String message) : super(message);
}
