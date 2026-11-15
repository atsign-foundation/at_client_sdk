import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_wasm/src/keys/envelope_exceptions.dart';
import 'package:at_client_wasm/src/keys/key_bytes_store.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:at_client_wasm/src/keys/web_at_keys_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('WebAtKeysIo', () {
    late InMemoryKeyBytesStore store;
    late PrfSecret secret;
    late PrfSecret wrongSecret;

    setUp(() {
      store = InMemoryKeyBytesStore();
      secret = PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));
      wrongSecret =
          PrfSecret(Uint8List.fromList(List.generate(32, (i) => i + 1)));
    });

    WebAtKeysIo createIo({UnlockSecret? s}) {
      return WebAtKeysIo(
        store,
        s ?? secret,
      );
    }

    test('write->read round-trip', () async {
      final io = createIo();
      final keys = legacyAtKeys(atsign: Atsign('@alice'));

      await io.write('@alice', keys);
      final readKeys = await io.read('@alice');

      expectLegacyAtKeys(readKeys, keys);
    });

    test('write twice throws', () async {
      final io = createIo();
      final keys = legacyAtKeys(atsign: Atsign('@alice'));

      await io.write('@alice', keys);
      await expectLater(
        () => io.write('@alice', keys),
        throwsA(isA<AtKeysFileOverwriteException>()),
      );
    });

    test('flush on absent writes', () async {
      final io = createIo();
      final keys = legacyAtKeys(atsign: Atsign('@alice'));

      await io.flush(Atsign('@alice'), keys);
      final readKeys = await io.read('@alice');

      expectLegacyAtKeys(readKeys, keys);
    });

    test('flush adding a field succeeds and reads back', () async {
      final io = createIo();
      final keys = legacyAtKeys(atsign: Atsign('@alice'));

      await io.write('@alice', keys);

      final keysToUpdate = await io.read('@alice');
      keysToUpdate.addKey(symmetricKey('new_key'));

      await io.flush(Atsign('@alice'), keysToUpdate);

      final updatedKeys = await io.read('@alice');
      expect(updatedKeys.atSignKeys, hasLength(1));
    });

    test(
        'flush that drops existing material is rejected by validateMapUpdate and leaves stored bytes unchanged',
        () async {
      final io = createIo();
      final keys = legacyAtKeys(atsign: Atsign('@alice'));
      keys.addKey(symmetricKey('important_key'));

      await io.write('@alice', keys);
      final originalBytes = await store.get('@alice');

      final keysToUpdate =
          legacyAtKeys(atsign: Atsign('@alice')); // Dropped important_key

      await expectLater(
        () => io.flush(Atsign('@alice'), keysToUpdate),
        throwsA(isA<AtKeysValidationException>()),
      );

      final bytesAfter = await store.get('@alice');
      expect(bytesAfter, originalBytes);
    });

    test('two atSigns in one store isolated', () async {
      final io = createIo();

      final aliceKeys = legacyAtKeys(atsign: Atsign('@alice'));
      final bobKeys = legacyAtKeys(atsign: Atsign('@bob'));

      await io.write('@alice', aliceKeys);
      await io.write('@bob', bobKeys);

      final readAlice = await io.read('@alice');
      final readBob = await io.read('@bob');

      expectLegacyAtKeys(readAlice, aliceKeys);
      expectLegacyAtKeys(readBob, bobKeys);
    });

    test('wrong secret on read -> EnvelopeUnlockFailedException', () async {
      final io = createIo();
      final keys = legacyAtKeys(atsign: Atsign('@alice'));

      await io.write('@alice', keys);

      final wrongIo = createIo(s: wrongSecret);
      await expectLater(
        () => wrongIo.read('@alice'),
        throwsA(isA<EnvelopeUnlockFailedException>()),
      );
    });
  });
}
