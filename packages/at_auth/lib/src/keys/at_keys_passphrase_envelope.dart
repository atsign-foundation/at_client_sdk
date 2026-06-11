import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

class AtKeysPassphraseEnvelopeCodec {
  final AtDecryptionException Function(String) _decryptionException;

  AtKeysPassphraseEnvelopeCodec({
    AtDecryptionException Function(String)? decryptionException,
  }) : _decryptionException = decryptionException ??
            ((message) => AtDecryptionException(message));

  bool isEnvelope(Map<String, dynamic> json) {
    return json.containsKey('iv');
  }

  Future<Map<String, dynamic>> decode(
    Map<String, dynamic> json, {
    String? passPhrase,
  }) async {
    if (!isEnvelope(json)) {
      return json;
    }
    if (passPhrase.isNullOrEmpty) {
      throw _decryptionException(
          'Pass Phrase is required for password protected atKeys file');
    }

    final atEncrypted = AtEncrypted.fromJson(json);
    if (atEncrypted.hashingAlgoType == null) {
      throw _decryptionException(
          'Hashing algo type is required for decryption of password protected atKeys file');
    }

    final String decryptedAtKeysData;
    try {
      decryptedAtKeysData = await AtKeysCrypto.fromHashingAlgorithm(
        atEncrypted.hashingAlgoType!,
      ).decrypt(atEncrypted, passPhrase!);
    } catch (e) {
      throw _decryptionException(
          'Failed to decrypt atKeys file - passphrase may be incorrect: $e');
    }

    final decodedJson = jsonDecode(decryptedAtKeysData);
    if (decodedJson is! Map<String, dynamic>) {
      throw AtKeysParseException(
          'Expected decrypted atKeys file to contain a JSON object');
    }
    return decodedJson;
  }
}
