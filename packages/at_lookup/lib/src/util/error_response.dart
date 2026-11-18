import 'dart:convert';

import 'package:at_lookup/src/exception/at_lookup_exception.dart';

final RegExp _leadingErrorCode = RegExp(r'^(AT\d{4})(?:[-:]|$)');

/// The [AtLookUpException] an atServer's `error:` [response] stands for.
///
/// [response] is the whole reply, `error:` included. An atServer writes its
/// body as `<code>-<text>`, as `<code>:<text>`, or as a JSON object whose
/// string `errorCode` and `errorDescription` are the code and the text; a
/// code at the head of the body is `AT` and four digits. Any other body is
/// read as `AT0014`, with the body in the text.
AtLookUpException errorResponseException(String response) {
  final body = response.replaceFirst(RegExp('^error:'), '');
  final leading = _leadingErrorCode.firstMatch(body);
  if (leading != null) {
    return AtLookUpException(leading[1]!, body.substring(leading.end));
  }
  final json = _decodedOrNull(body);
  if (json is Map && json['errorCode'] is String) {
    return AtLookUpException(
        json['errorCode'], '${json['errorDescription'] ?? ''}');
  }
  return AtLookUpException('AT0014', 'Unknown server error: $body');
}

Object? _decodedOrNull(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

final RegExp _jsonLeadingErrorCode =
    RegExp(r'^\{\s*"errorCode"\s*:\s*"(AT\d{4})"');

/// The atServer's error code in [message], which carries its `error:` reply
/// in any of the forms an atServer writes: `error:<code>-<text>`,
/// `error:<code>:<text>` or `error:{"errorCode":"<code>",...}`. Null when it
/// carries none.
///
/// The reply is what follows the first `error:`. A JSON reply is read whole,
/// and its `errorCode` counts when a string; one that does not parse, as when
/// other text follows it, counts only when `errorCode` is its first key, so a
/// code in its `errorDescription` is never read.
String? atServerErrorCodeIn(String message) {
  final at = message.indexOf('error:');
  if (at < 0) return null;
  final body = message.substring(at + 'error:'.length);
  if (!body.startsWith('{')) return _leadingErrorCode.firstMatch(body)?[1];
  final json = _decodedOrNull(body);
  if (json != null) {
    return json is Map && json['errorCode'] is String
        ? json['errorCode']
        : null;
  }
  return _jsonLeadingErrorCode.firstMatch(body)?[1];
}
