import 'dart:convert';
import 'dart:typed_data';
import 'package:at_chops/at_chops.dart';
import 'package:at_client_wasm/src/keys/envelope_exceptions.dart';
import 'package:at_client_wasm/src/keys/key_envelope.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import '../../tool/src/cut.dart';
import '../test_utils.dart';

void main() {
  group('cut_keys', () {
    test('cutEnvelope seals keys with passphrase', () async {
      final keys = legacyAtKeys(atsign: Atsign('@alice'));
      final codec = KeyEnvelopeCodec(
          passphraseParams:
              Argon2idParams(memoryKiB: 12, iterations: 1, parallelism: 1));
      final result = await cutEnvelope(keys, codec: codec);

      expect(result.envelope, isNotEmpty);
      expect(result.passphrase.passphrase, isNotEmpty);

      final opened =
          await codec.open('@alice', result.envelope, result.passphrase);
      expect(opened.plaintext, equals(keys.toJson()));

      final jsonEnvelope =
          jsonDecode(utf8.decode(result.envelope)) as Map<String, dynamic>;
      final unlocks = jsonEnvelope['unlocks'] as List;
      expect(unlocks.length, 1);
      expect(unlocks[0]['kind'], 'passphrase');

      await expectLater(
        codec.open('@alice', result.envelope, PrfSecret(Uint8List(32))),
        throwsA(isA<NoMatchingUnlockException>()),
      );
    });

    test('two cuts produce different passphrases and different envelopes',
        () async {
      final keys = legacyAtKeys(atsign: Atsign('@alice'));
      final codec = KeyEnvelopeCodec(
          passphraseParams:
              Argon2idParams(memoryKiB: 12, iterations: 1, parallelism: 1));

      final result1 = await cutEnvelope(keys, codec: codec);
      final result2 = await cutEnvelope(keys, codec: codec);

      expect(result1.passphrase.passphrase,
          isNot(equals(result2.passphrase.passphrase)));
      expect(result1.envelope, isNot(equals(result2.envelope)));
    });

    test('atKeysRecordKey generates valid keys', () {
      expect(atKeysRecordKey('alice', 'myapp'), '_atkeys.myapp@alice');
      expect(atKeysRecordKey('@alice', 'myapp'), '_atkeys.myapp@alice');

      expect(() => atKeysRecordKey('alice', ''), throwsArgumentError);
      expect(() => atKeysRecordKey('alice', 'my:app'), throwsArgumentError);
      expect(() => atKeysRecordKey('alice', 'my@app'), throwsArgumentError);
      expect(() => atKeysRecordKey('alice', 'my app'), throwsArgumentError);
      expect(() => atKeysRecordKey('alice', '.myapp'), throwsArgumentError);
      expect(() => atKeysRecordKey('alice', 'myapp.'), throwsArgumentError);
    });

    test('updateCommand formats correctly', () {
      final envelopeStr = '{"some":"compact"}';
      final envelope = utf8.encode(envelopeStr);
      final cmd = updateCommand('alice', 'myapp', envelope);

      expect(cmd.startsWith('update:public:_atkeys.myapp@alice '), isTrue);
      expect(cmd.endsWith('\n'), isTrue);
      expect(cmd.substring(0, cmd.length - 1).contains('\n'), isFalse);
      expect(cmd.contains(envelopeStr), isTrue);
    });

    test('updateCommand rejects envelopes with newlines', () {
      final envelopeStr = '{"some":\n"compact"}';
      final envelope = utf8.encode(envelopeStr);
      expect(() => updateCommand('alice', 'myapp', envelope), throwsStateError);
    });
  });
}
