// The retrofit surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use, deprecated_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// A client that holds NO enrollment gives itself one — driven through
/// `AtClientImpl.create`, not through the pieces.
///
/// ⛔ **Why this exists beside the live proof.** The end-to-end behaviour is
/// pinned by `tests/at_onboarding_cli_functional_tests`'
/// `pq_pre_enrollment_retrofit_test.dart`, which needs Docker, a virtualenv and
/// a CRAM secret that works once per image. Nothing in this package drove the
/// decision at all: re-adding the `enrollmentId == null` return that this
/// behaviour replaced would leave every unit test in at_client green, and only
/// a live pack on a separate CI job would notice.
///
/// **What is asserted is the `enroll:request` the client puts on the wire**,
/// not that it "tried". A test that asserted an attempt would be asserting the
/// test double; the command carries the app, the device and the grants this
/// client chose for itself, and those are the decisions worth pinning.
///
/// The retrofit does not COMPLETE here — re-authenticating under the new
/// enrollment needs an atServer, and the unroutable root domain below makes
/// that fail fast. That is deliberate: the failure lands in
/// `_settleEnrollmentIdentity`'s own guard, which is the documented behaviour,
/// and everything under test has already happened.
void main() {
  late final AtEncryptionKeyPair encryptionKeyPair;
  late final AtPkamKeyPair pkamKeyPair;
  late final String selfKey;

  setUpAll(() {
    registerFallbackValue(FakeLookupVerbBuilder());
    // Real keys: the client wraps its new enrollment's symmetric key to this
    // encryption public key, and a stub would not survive that.
    encryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    selfKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
  });

  void dropCachedClients(String atSign) {
    AtClientImpl.atClientInstanceMap.removeWhere((key, _) =>
        key == atSign || (key is String && key.startsWith('$atSign|')));
  }

  /// The keyfile a legacy onboarding left behind: flat fields, no enrollment.
  AtKeys legacyKeys() => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(pkamKeyPair.atPublicKey.publicKey)
    ..apkamPrivateKey = AtBytes.fromString(pkamKeyPair.atPrivateKey.privateKey)
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(encryptionKeyPair.atPublicKey.publicKey)
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(encryptionKeyPair.atPrivateKey.privateKey)
    ..defaultSelfEncryptionKey = AtBytes.fromString(selfKey);

  AtClientPreference preferenceAt(PqPosture posture, String atSign) =>
      AtClientPreference(posture: posture)
        ..hiveStoragePath = 'test/hive/$atSign'
        ..commitLogPath = 'test/hive/$atSign/commit'
        // Unroutable on purpose: the retrofit's final step re-authenticates
        // under the new enrollment, which needs a real atServer. Failing fast
        // here keeps this test off the network and off any clock.
        ..rootDomain = '127.0.0.1'
        ..rootPort = 1;

  /// Builds a client for [atSign] at [posture] holding NO enrollment id, and
  /// returns every command its connection was asked to execute.
  Future<List<String>> commandsFromStartup(
      String atSign, PqPosture posture) async {
    dropCachedClients(atSign);
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, legacyKeys());

    final mockLookUp = MockAtLookupImpl();
    when(() => mockLookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async =>
            'data:{"enrollmentId":"new-from-nothing","status":"approved"}');

    final mockRemote = MockRemoteSecondary();
    when(() => mockRemote.atLookUp).thenReturn(mockLookUp);
    when(() => mockRemote.executeVerb(any()))
        .thenAnswer((_) async => 'data:ok');

    final chops = AtChopsImpl(AtChopsKeys.create(encryptionKeyPair, pkamKeyPair)
      ..selfEncryptionKey = AESKey(selfKey));

    await AtClientImpl.create(atSign, 'buzz', preferenceAt(posture, atSign),
        remoteSecondary: mockRemote, atChops: chops, atKeysIo: keysIo);

    final captured = <String>[];
    try {
      captured.addAll(verify(() =>
              mockLookUp.executeCommand(captureAny(), auth: any(named: 'auth')))
          .captured
          .cast<String>());
    } on TestFailure {
      // verify() throws when the mock was never called, which is precisely
      // what the legacy arm expects. An empty list says it.
    }
    return captured;
  }

  test('a client holding no enrollment asks the atServer for one', () async {
    final commands = await commandsFromStartup('@alice', PqPosture.pqReady);

    final request = commands.firstWhere((c) => c.startsWith('enroll:request:'),
        orElse: () => throw TestFailure(
            'a client with no enrollment id, at a posture that wants ML-DSA '
            'authentication, sent no enroll:request. Commands seen: '
            '$commands'));
    final params =
        jsonDecode(request.substring('enroll:request:'.length).trim())
            as Map<String, dynamic>;

    expect(params['appName'], 'firstApp',
        reason: 'this IS the atSign\'s first enrollment in everything but the '
            'path that creates it');
    expect(params['deviceName'], startsWith('firstDevice-'));
    expect(params['deviceName'], isNot('firstDevice'),
        reason: 'the bare constant collides across sibling clones of one '
            'keyfile and the atServer refuses every one after the first');
    expect(params['namespaces'], {'*': 'rw', '__manage': 'rw'},
        reason: 'the connection asking has proved possession of the atSign\'s '
            'own root credential and is unscoped, so there is nothing '
            'narrower to bound the first enrollment by');
    expect(params['encryptedAPKAMSymmetricKey'], isNotNull,
        reason: 'the atServer parks this request pending, so the client has to '
            'approve it — and approving needs the encryption keys wrapped '
            'under a symmetric key. An APKAM retrofit, which conveys nothing, '
            'sends none');
  }, timeout: Timeout(Duration(minutes: 2)));

  /// The control, and it can go red while the assertions above stay green: the
  /// same keyfile, the same absence of an enrollment, only the posture differs.
  test('at a legacy posture the same client asks for nothing', () async {
    final commands = await commandsFromStartup('@bob', PqPosture.legacy);

    expect(commands.where((c) => c.startsWith('enroll:request:')), isEmpty,
        reason: 'legacy means "do not drive an upgrade"; a client that enrols '
            'here would be converting an atSign whose app asked it not to. '
            'Commands seen: $commands');
  }, timeout: Timeout(Duration(minutes: 2)));
}
