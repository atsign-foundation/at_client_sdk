/// Which signer a client's remote connection authenticates with.
///
/// A client built from a keyfile also derives an `AtChops` from it, and the
/// connection used to inject that `AtChops` as the PKAM signer — so a keyfile
/// client's own connection never signed from the keyfile. The keyfile is the
/// source; the `AtChops` is the door for a client that has no keyfile.
///
/// The instrument is at_chops' RSA verifier: the two sources hold different
/// keypairs, and which public key the PKAM signature verifies under says which
/// source signed. A lookup without the authenticator seam is covered in
/// `remote_secondary_test.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// `AtLookupImpl` implements `AtLookupMuxable`, so this double has the seam.
class MockMuxableLookUp extends Mock implements AtLookupImpl {}

/// The frozen interface alone: no authenticator seam, only the credential
/// fields.
class MockPlainLookUp extends Mock implements AtLookUp {}

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
  late RsaKeyPair chopsPair;

  setUpAll(() {
    keyfilePair = RsaKeyPair.generate();
    chopsPair = RsaKeyPair.generate();
  });

  /// A legacy-shaped keyfile whose APKAM keypair is [keyfilePair].
  Future<InMemoryAtKeysIo> keyfile() async {
    final io = InMemoryAtKeysIo();
    await io.write(
        atSign,
        AtKeys()
          ..apkamPublicKey =
              AtBytes.fromString(keyfilePair.atPublicKey.publicKey)
          ..apkamPrivateKey =
              AtBytes.fromString(keyfilePair.atPrivateKey.privateKey));
    return io;
  }

  /// An `AtChops` holding [pair]: the door for a client built without a
  /// keyfile, and the thing a keyfile client derives and must not sign with.
  // ignore: deprecated_member_use
  AtChops chopsOf(RsaKeyPair pair) => AtChopsImpl(AtChopsKeys.create(
      null,
      // ignore: deprecated_member_use
      AtPkamKeyPair.create(
          pair.atPublicKey.publicKey, pair.atPrivateKey.privateKey)));

  /// Runs the authenticator [lookUp] was handed against [challenge] and
  /// returns the signature the `pkam:` verb carried.
  Future<Uint8List> pkamSignatureBy(MockMuxableLookUp lookUp) async {
    final installed = verify(() => lookUp.authenticator = captureAny())
        .captured
        .last as AtAuthenticator;
    final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
    expect(await installed(executor), isTrue);
    final pkam = executor.sent.last;
    return base64Decode(pkam.substring(pkam.lastIndexOf(':') + 1).trim());
  }

  Future<bool> verifiesUnder(RsaKeyPair pair, Uint8List signature) =>
      RsaSignatureAlgo.rsa2048().verifyBytes(
          Uint8List.fromList(utf8.encode(challenge)),
          signature: signature,
          publicKey: base64Decode(pair.atPublicKey.publicKey));

  group('which signer the remote connection authenticates with', () {
    test('the keyfile, for a client holding a keyfile and an AtChops',
        () async {
      final lookUp = MockMuxableLookUp();
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp,
          atChops: chopsOf(chopsPair),
          atKeysIo: await keyfile());

      final signature = await pkamSignatureBy(lookUp);

      expect(await verifiesUnder(keyfilePair, signature), isTrue,
          reason: 'the keyfile is the source; a keyfile client\'s AtChops was '
              'derived from it and is not a second credential');
      expect(await verifiesUnder(chopsPair, signature), isFalse,
          reason: 'the control: the two pairs differ, so one verifier says no');
    });

    test('the keyfile, for a client holding only a keyfile', () async {
      final lookUp = MockMuxableLookUp();
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp, atKeysIo: await keyfile());

      expect(await verifiesUnder(keyfilePair, await pkamSignatureBy(lookUp)),
          isTrue);
    });

    test('the AtChops, for a client holding no keyfile', () async {
      // The door, kept open while clients built from an AtChops exist.
      final lookUp = MockMuxableLookUp();
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp, atChops: chopsOf(chopsPair));

      expect(await verifiesUnder(chopsPair, await pkamSignatureBy(lookUp)),
          isTrue);
    });

    test('a lookup without the seam keeps the credential fields', () async {
      // at_lookup's ladder, which such a lookup authenticates from; the
      // fields stay written and leave with the ladder in the at_lookup major.
      final lookUp = MockPlainLookUp();
      final chops = chopsOf(chopsPair);
      RemoteSecondary(atSign, preference,
          atLookUp: lookUp, atChops: chops, atKeysIo: await keyfile());

      verify(() => lookUp.atChops = chops).called(1);
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
      when(() => client.atChops).thenReturn(chopsOf(chopsPair));
    });

    test('carries no AtChops when the client has a keyfile', () async {
      when(() => client.atKeysIo).thenReturn(await keyfile());

      final remote = SyncServiceImpl.remoteSecondaryFor(client);

      expect(remote.atChops, isNull,
          reason: 'the keyfile is the credential sync authenticates with');
    });

    test('carries the AtChops for a client built without one', () {
      when(() => client.atKeysIo).thenReturn(null);

      final remote = SyncServiceImpl.remoteSecondaryFor(client);

      expect(remote.atChops, same(client.atChops),
          reason: 'the door for a client built from an AtChops');
    });
  });
}
