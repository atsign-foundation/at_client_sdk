import 'package:at_commons/at_commons.dart';

/// Utility class that returns instance of exception for the given error code.
class AtExceptionUtils {
  /// Returns the instance of exception for the given error code.
  /// Defaults to return an instance of [AtException]
  static AtException get(String errorCode, String errorDescription) {
    switch (errorCode) {
      case 'AT0001':
        return AtServerException(errorDescription);
      case 'AT0003':
        return InvalidSyntaxException(errorDescription);
      case 'AT0005':
        return BufferOverFlowException(errorDescription);
      case 'AT0006':
        return OutboundConnectionLimitException(errorDescription);
      case 'AT0007':
        return SecondaryNotFoundException(errorDescription);
      case 'AT0008':
        return HandShakeException(errorDescription);
      case 'AT0009':
        return UnAuthorizedException(errorDescription);
      case 'AT0010':
        return InternalServerError(errorDescription);
      case 'AT0011':
        return InternalServerException(errorDescription);
      case 'AT0012':
        return InboundConnectionLimitException(errorDescription);
      case 'AT0013':
        return BlockedConnectionException(errorDescription);
      case 'AT0015':
        return KeyNotFoundException(errorDescription);
      case 'AT0021':
        return SecondaryConnectException(errorDescription);
      case 'AT0022':
        return IllegalArgumentException(errorDescription);
      case 'AT0023':
        return AtTimeoutException(errorDescription);
      case 'AT0024':
        return ServerIsPausedException(errorDescription);
      case 'AT0028':
        return AtThrottleLimitExceeded(errorDescription);
      case 'AT0029':
        return AtInvalidEnrollmentException(errorDescription);
      case 'AT0031':
        return AtEnrollmentRevokeException(errorDescription);
      case 'AT0032':
        return IllegalStateException(errorDescription);
      case 'AT0401':
        return UnAuthenticatedException(errorDescription);
      default:
        return AtException(errorDescription);
    }
  }
}
