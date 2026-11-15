import 'dart:convert';

import 'package:at_lookup/src/exception/at_lookup_exception.dart';

/// The [AtLookUpException] an atServer's `error:` [response] stands for.
///
/// [response] is the whole reply, `error:` included. Its body is JSON with an
/// `errorCode` and an `errorDescription`, or, from an older atServer,
/// `<code>-<description>`.
AtLookUpException errorResponseException(String response) {
  final body = response.replaceFirst(RegExp('^error:'), '');
  // Setting the errorCode and errorDescription to default values.
  var errorCode = 'AT0014';
  var errorDescription = 'Unknown server error';
  try {
    var errorMap = jsonDecode(body);
    errorCode = errorMap['errorCode'];
    errorDescription = errorMap['errorDescription'];
  } on FormatException {
    // Catching the FormatException to preserve backward compatibility - responses without jsonEncoding.
    // TODO: Can we remove the below catch block in next release once all the servers are migrated to new version.
    if (body.contains('-')) {
      errorCode = body.substring(0, body.indexOf('-'));
      errorDescription = body.substring(body.indexOf('-') + 1);
    } else {
      errorDescription += ": $body";
    }
  }
  return AtLookUpException(errorCode, errorDescription);
}
