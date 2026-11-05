import 'package:at_commons/at_commons.dart';

/// AtLookUpException class
class AtLookUpException implements Exception {
  String errorCode;
  String errorMessage;

  AtLookUpException(this.errorCode, this.errorMessage);

  @override
  String toString() {
    return 'ErrorCode: $errorCode - Exception: $errorMessage';
  }
}

/// AtLookUpExceptionUtil to get ErrorCode and ErrorDescription
class AtLookUpExceptionUtil {
  /// Returns ErrorCode String
  ///
  /// An [AtIOException], which a transport's failed write is, and a
  /// [ConnectionInvalidException], which a lost connection is, take the code
  /// of a socket error.
  static String getErrorCode(Exception exception) {
    if (exception is AtIOException || exception is ConnectionInvalidException) {
      return error_codes['SocketException']!;
    }
    var errorCode = error_codes[exception.runtimeType.toString()];
    errorCode ??= 'AT0014';
    return errorCode;
  }

  /// Returns ErrorDescription String
  static String? getErrorDescription(String errorCode) {
    return error_description[errorCode];
  }
}
