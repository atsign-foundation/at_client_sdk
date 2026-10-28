/// Which signer a client's remote connection authenticates with.
///
/// The keyfile is the source; a bare private key signs only for a client that
/// has no keyfile.
///
/// The instrument is at_chops' RSA verifier: the two sources hold different
/// keypairs, and which public key the PKAM signature verifies under says which
/// source signed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// `AtLookupImpl` implements `AtLookupMuxable`, so this double has the seam.
class MockMuxableLookUp extends Mock implements AtLookupImpl {}

/// Runs an installed [AtAuthenticator] for real and records what it sent.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}

void main() {
  const atSign = '@alice';

  /// A `from:` challenge naming [atSign], as the atServer issues one.
  const challenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581@alice'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';
  final preference = AtClientPreference()..namespace = 'unit';

  late RsaKeyPair keyfilePair;
  late RsaKeyPair privateKeyPair;

  setUpAll(() {
    keyfilePair = RsaKeyPair.generate();
    privateKeyPair = RsaKeyPair.generate();
  });

  /// A legacy-shaped keyfile whose APKAM keypair is [keyfilePair].
  Future<InMemoryAtKeysIo> keyfile() async {
    final io = InMemoryAtKeysIo();
    await io.write(
        atSign,
        AtKeys.legacy(
            apkamPublicKey: keyfilePair.atPublicKey.publicKey,
            apkamPrivateKey: keyfilePair.atPrivateKey.privateKey));
    return io;
  }

  /// Runs [authenticate] against [challenge] and returns the signature the
  /// `pkam:` verb carried.
  Future<Uint8List> signatureFrom(AtAuthenticator authenticate) async {
    final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
    expect(await authenticate(executor), isTrue);
    final pkam = executor.sent.last;
    return base64Decode(pkam.substring(pkam.lastIndexOf(':') + 1).trim());
  }

  /// Runs the authenticator [lookUp] was handed against [challenge] and
  /// returns the signature the `pkam:` verb carried.
  Future<Uint8List> pkamSignatureBy(MockMuxableLookUp lookUp) async {
    final installed = verify(() => lookUp.authenticator = captureAny())
        .captured
        .last as AtAuthenticator;
    return signatureFrom(installed);
  }

  Future<bool> verifiesUnder(RsaKeyPair pair, Uint8List signature) =>
      RsaSignatureAlgo.rsa2048().verifyBytes(
          Uint8List.fromList(utf8.encode(challenge)),
          signature: signature,
          publicKey: base64Decode(pair.atPublicKey.publicKey));

  group('which signer the remote connection authenticates with', () {
    test('the keyfile, for a client holding a keyfile and a private key',
        () async {
      final lookUp = MockMuxableLookUp();
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp,
          privateKey: privateKeyPair.atPrivateKey.privateKey,
          atKeysIo: await keyfile());

      final signature = await pkamSignatureBy(lookUp);

      expect(await verifiesUnder(keyfilePair, signature), isTrue,
          reason: 'the keyfile is the source; a private key beside it is not '
              'a second credential');
      expect(await verifiesUnder(privateKeyPair, signature), isFalse,
          reason: 'the control: the two pairs differ, so one verifier says no');
    });

    test('the keyfile, for a client holding only a keyfile', () async {
      final lookUp = MockMuxableLookUp();
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp, atKeysIo: await keyfile());

      expect(await verifiesUnder(keyfilePair, await pkamSignatureBy(lookUp)),
          isTrue);
    });

    test('nothing, for a client whose keyfile holds no keypair', () async {
      final lookUp = MockMuxableLookUp();
      final empty = InMemoryAtKeysIo();
      await empty.write(atSign, AtKeys());
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp,
          privateKey: privateKeyPair.atPrivateKey.privateKey,
          atKeysIo: empty);
      final installed = verify(() => lookUp.authenticator = captureAny())
          .captured
          .last as AtAuthenticator;
      final executor = _RecordingExecutor(['data:$challenge', 'data:success']);

      await expectLater(
          installed(executor), throwsA(isA<AtKeyNotFoundException>()));
      expect(executor.sent.where((c) => c.startsWith('pkam:')), isEmpty,
          reason: 'a keyfile client signs from its keyfile or not at all');
    });

    test('the private key, for a client holding no keyfile', () async {
      final lookUp = MockMuxableLookUp();
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp, privateKey: privateKeyPair.atPrivateKey.privateKey);

      expect(await verifiesUnder(privateKeyPair, await pkamSignatureBy(lookUp)),
          isTrue);
    });
  });

  group('the remote sync builds for itself', () {
    late MockAtClient client;

    setUp(() {
      // Building a remote without a lookup asks the manager for an address
      // finder, as remote_secondary_test does.
      final finder = MockSecondaryAddressFinder();
      when(() => finder.findSecondary(any())).thenAnswer(
          (_) async => SecondaryAddress('fake.secondary.address', 8010));
      AtClientManager.getInstance().secondaryAddressFinder = finder;

      // getPreferences() is a concrete override on MockAtClient and answers
      // its own preference, so it is not stubbed here.
      client = MockAtClient();
      when(() => client.getCurrentAtSign()).thenReturn(atSign);
      when(() => client.enrollmentId).thenReturn(null);
    });

    test('signs with the client\'s keyfile', () async {
      when(() => client.atKeysIo).thenReturn(await keyfile());

      final remote = SyncServiceImpl.remoteSecondaryFor(client);

      expect(remote.atLookUp, isA<AtLookupMuxable>());
      expect(
          await verifiesUnder(
              keyfilePair, await signatureFrom(remote.atLookUp.authenticator!)),
          isTrue);
    });
  });
}
