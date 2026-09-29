import 'dart:convert';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:http/http.dart' as http;

/// Where the issuer runs: `ee/up.sh` starts it beside the Ephemeral
/// Environment. It stands in for a registrar.
const String issuerUrl = 'http://localhost:35100';

/// A new atSign, with the CRAM secret that activates it.
typedef IssuedAtSign = ({
  String atSign,
  String cramKey,
  AtRootDomain rootDomain,
});

/// Asks the issuer for the next atSign it has not issued.
Future<IssuedAtSign> issueAtSign() async {
  final response = await http.post(Uri.parse('$issuerUrl/atsigns'));
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200) {
    throw StateError('The issuer refused: ${body['error']}');
  }
  return (
    atSign: body['atSign'] as String,
    cramKey: body['cramKey'] as String,
    rootDomain: AtRootDomain.parse(body['rootDomain'] as String),
  );
}
