import 'package:at_commons/at_commons.dart';

class AtClientExceptionUtil {
  static String getErrorCode(Exception exception) {
    var errorCode = error_codes[exception.runtimeType.toString()];
    errorCode ??= 'AT0014';
    return errorCode;
  }

  static String? getErrorDescription(String errorCode) {
    return error_description[errorCode];
  }
}
