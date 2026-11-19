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
