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
