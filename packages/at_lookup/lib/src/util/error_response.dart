import 'dart:convert';

import 'package:at_lookup/src/exception/at_lookup_exception.dart';

final RegExp _leadingErrorCode = RegExp(r'^(AT\d{4})(?:[-:]|$)');

/// The code an atServer's `error:` [response] names, or null when
/// [response] is not an `error:` reply or names none.
///
/// [response] is the whole reply, `error:` included. An atServer writes its
/// body as `<code>-<text>`, as `<code>:<text>`, or as a JSON object whose
/// string `errorCode` and `errorDescription` are the code and the text; a
/// code at the head of the body is `AT` and four digits, followed by `-`,
/// `:` or the end of the reply.
String? errorResponseCode(String response) => response.startsWith('error:')
    ? _namedError(_bodyOf(response))?.code
    : null;

/// The [AtLookUpException] an atServer's `error:` [response] stands for.
///
/// [response] is the whole reply, `error:` included, and is read as
/// [errorResponseCode] reads it. A body that names no code is read as
/// `AT0014`, with the body in the text.
AtLookUpException errorResponseException(String response) {
  final body = _bodyOf(response);
  final named = _namedError(body);
  return named == null
      ? AtLookUpException('AT0014', 'Unknown server error: $body')
      : AtLookUpException(named.code, named.text);
}

String _bodyOf(String response) => response.replaceFirst(RegExp('^error:'), '');

({String code, String text})? _namedError(String body) {
  final leading = _leadingErrorCode.firstMatch(body);
  if (leading != null) {
    return (code: leading[1]!, text: body.substring(leading.end));
  }
  final json = _decodedOrNull(body);
  if (json is Map && json['errorCode'] is String) {
    return (
      code: json['errorCode'] as String,
      text: '${json['errorDescription'] ?? ''}'
    );
  }
  return null;
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
