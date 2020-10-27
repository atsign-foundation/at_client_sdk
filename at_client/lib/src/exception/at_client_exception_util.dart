import 'package:at_commons/at_commons.dart';

class AtClientExceptionUtil {
  static String getErrorCode(Exception exception) {
    var error_code = error_codes[exception.runtimeType.toString()];
    error_code ??= 'AT0014';
    return error_code;
  }

  static String getErrorDescription(String error_code) {
    return error_description[error_code];
  }
}
