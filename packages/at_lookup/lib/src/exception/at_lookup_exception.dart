import 'package:at_commons/at_commons.dart';

/// AtLookUpException class
class AtLookUpException implements Exception {
  String errorCode;
  String errorMessage;

  /// The failure [AtLookUp.executeVerb] caught and threw as this exception,
  /// or null when it wraps none, as for an atServer's `error:` reply.
  final Object? cause;

  AtLookUpException(this.errorCode, this.errorMessage, {this.cause});

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
  /// of a socket error, and an [UnAuthenticatedException] of any subtype the
  /// code of a failed authentication. An [AtLookUpException], which a proxy
  /// root's refused `from:` preamble is, keeps the code it already carries.
  static String getErrorCode(Exception exception) {
    if (exception is AtLookUpException) {
      return exception.errorCode;
    }
    if (exception is AtIOException || exception is ConnectionInvalidException) {
      return error_codes['SocketException']!;
    }
    if (exception is UnAuthenticatedException) {
      return error_codes['UnAuthenticatedException']!;
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
