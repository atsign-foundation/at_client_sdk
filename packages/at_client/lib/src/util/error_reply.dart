import 'dart:convert';

final RegExp _leadingErrorCode = RegExp(r'^AT\d{4}');

/// The atServer's error code in [message], which carries its `error:` reply
/// in any of the forms an atServer writes: `error:<code>-<text>`,
/// `error:<code>:<text>` or `error:{"errorCode":"<code>",...}`. Null when it
/// carries none.
String? atServerErrorCodeIn(String message) {
  final at = message.indexOf('error:');
  if (at < 0) return null;
  final body = message.substring(at + 'error:'.length);
  if (!body.startsWith('{')) return _leadingErrorCode.stringMatch(body);
  try {
    final code = jsonDecode(body)['errorCode'];
    return code is String ? code : null;
  } on FormatException {
    return null;
  }
}
