import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookup extends Mock implements AtLookUp {}

class MockAtLookUpImpl extends Mock implements AtLookupImpl {}

class MockAtChops extends Mock implements AtChops {}

class MockAtChopsKeys extends Mock implements AtChopsKeys {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockCryptoProvider extends Mock implements CryptoProvider {}

class FakeCryptoProvider extends Fake implements CryptoProvider {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  // A stable, mutable preference (matching the real getPreferences(), which
  // returns the live instance) so tests can set `.crypto` to inject a
  // CryptoConfig that CryptoRuntime resolves against.
  final AtClientPreference _preference = AtClientPreference()
    ..namespace = 'wavi';

  @override
  AtClientPreference getPreferences() => _preference;
}

class MockAtClientImpl extends Mock implements AtClientImpl {}

/// `AtKeysIo` is `sealed`, but that only restricts direct subtyping of the
/// base — `WrittenAtKeysIo` is an ordinary `abstract class`, so extending it
/// outside at_auth is legal. Both methods throw so any accidental key IO in
/// the S-2 seam fails loudly (the stub doubles as the behaviour-neutrality
/// proof). Deliberately does NOT override `flush` (not present on the
/// at_auth version this branch compiles against).
class StubAtKeysIo extends WrittenAtKeysIo {
  @override
  Future<AtKeys> read(String atSign) => throw UnimplementedError();

  @override
  Future<void> write(String atSign, AtKeys atKeys) =>
      throw UnimplementedError();
}

/// Example of a [CryptoProvider] that consumes the S-2 `context.io` seam.
///
/// Unlike the built-in legacy provider (which still pulls key material off the
/// client), this one sources its key from the injected [AtKeysIo]: it reads the
/// current atSign's [AtKeys] and uses `defaultSelfEncryptionKey` as a symmetric
/// key. This is the intended shape for providers once store wiring lands — the
/// provider never touches the client's atChops, only `context.io`.
///
/// The crypto here is a toy (repeating-key XOR) purely to keep the seam usage
/// legible; a real provider would feed the key material into AES/GCM or a
/// ratchet. Pair it with a functional `AtKeysIo` (one whose `read` returns a
/// canned [AtKeys], not the throwing [StubAtKeysIo]) to exercise a round trip.
class KeysSeamCryptoProvider implements CryptoProvider {
  static const providerId = 'keys-seam-demo';

  @override
  String get id => providerId;

  /// Pulls the self-encryption key bytes out of the injected key source.
  /// Throws if the seam was never injected — this provider has no fallback to
  /// the client, which is the whole point of moving off it.
  Future<List<int>> _keyBytes(CryptoContext context) async {
    final io = context.io;
    if (io == null) {
      throw AtEncryptionException(
        '$providerId requires an AtKeysIo on context.io (none injected)',
      );
    }
    final atSign = context.atClient.getCurrentAtSign()!;
    final atKeys = await io.read(atSign);
    final selfKey = atKeys.defaultSelfEncryptionKey;
    if (selfKey == null) {
      throw AtEncryptionException(
        '$providerId: AtKeys has no defaultSelfEncryptionKey',
      );
    }
    return utf8.encode(selfKey.toString());
  }

  List<int> _xor(List<int> data, List<int> key) => [
        for (var i = 0; i < data.length; i++) data[i] ^ key[i % key.length],
      ];

  @override
  Future<String> encrypt(
    CryptoContext context,
    AtKey atKey,
    String plaintext,
  ) async {
    final key = await _keyBytes(context);
    final cipher = _xor(utf8.encode(plaintext), key);
    atKey.metadata.appMetadata = AppMetadata(providerId: id, additional: {
      'v': 1,
    });
    return base64.encode(cipher);
  }

  @override
  Future<String> decrypt(
    CryptoContext context,
    AtKey atKey,
    String ciphertext,
  ) async {
    if (atKey.metadata.appMetadata?.additional?['v'] != 1) {
      throw AtDecryptionException('Unsupported $providerId format');
    }
    final key = await _keyBytes(context);
    return utf8.decode(_xor(base64.decode(ciphertext), key));
  }
}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}
