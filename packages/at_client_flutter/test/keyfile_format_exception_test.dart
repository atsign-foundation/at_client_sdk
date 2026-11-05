import 'dart:convert';
import 'dart:io';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keyfile that does not parse, as an app built on this package meets it.
///
/// Catalogue: features/at_auth/keyfile_not_json.feature
void main() {
  test('An app built on at_client_flutter matches it by its fields', () async {
    final dir = Directory.systemTemp.createTempSync('keyfile_format_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/@alice_key.atKeys';
    const text = '{"aesPkamPublicKey":"cut short partway through';
    File(path).writeAsStringSync(text);
    late final FormatException parserError;
    try {
      jsonDecode(text);
    } on FormatException catch (e) {
      parserError = e;
    }

    try {
      await FileAtKeysIo(filePath: (_) => path).read('@alice');
      fail('the read succeeded');
    } on AtKeysFormatException catch (e) {
      expect(e.reason, parserError.message);
      expect(e.position, text.length + 1);
    }
  });
}
