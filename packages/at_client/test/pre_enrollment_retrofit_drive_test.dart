// The retrofit surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use, deprecated_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// A client that holds NO enrollment gives itself one — driven through
/// `AtClientImpl.create`, not through the pieces.
///
/// What is asserted is the `enroll:request` the client puts on the wire, not
/// that it tried: the command carries the app, the device and the grants this
/// client chose for itself.
void main() {
  late final AtEncryptionKeyPair encryptionKeyPair;
  late final AtPkamKeyPair pkamKeyPair;
  late final String selfKey;

  setUpAll(() {
    registerFallbackValue(FakeLookupVerbBuilder());
    // NOTE: real keys — the client wraps its new enrollment's symmetric key to
    // this encryption public key, and a stub would not survive that.
    encryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    selfKey = AESKey.generate(32).key;
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
        // NOTE: unroutable as a backstop. The refusal below stops the
        // retrofit before the step that would dial this, so nothing should
        // reach it - and if anything ever does, it must fail rather than
        // find something to talk to.
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
    // NOTE: the answer must REFUSE. This test asserts the command the client
    // put on the wire, which mocktail has captured before the answer is
    // given, so the answer's only job is to decide how far the retrofit then
    // runs. An approval sends it to a final step that re-authenticates
    // through a real at_lookup against `rootDomain`, not through this mock.
    // A failed retrofit is deliberately not fatal, so the client still comes
    // up either way.
    when(() => mockLookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async => 'error:AT0011-Internal server exception');

    final mockRemote = MockRemoteSecondary();
    when(() => mockRemote.atLookUp).thenReturn(mockLookUp);
    // NOTE: answered by VERB, because the shapes differ and a caller cannot
    // take the wrong one. A scan returns a JSON array and an empty one is an
    // empty roster; a lookup of a record nothing stored returns `data:null`.
    // A single blanket answer put the other shape in front of a caller each
    // way round - `data:ok` was json-decoded as a payload and failed, and
    // `data:null` reached `getKeys`, which builds a List from whatever the
    // scan decoded to.
    when(() => mockRemote.executeVerb(any())).thenAnswer((inv) async =>
        inv.positionalArguments[0] is ScanVerbBuilder
            ? 'data:[]'
            : 'data:null');
    // An empty roster: this atSign has no other enrollment to convey to, so
    // the seeding step has nobody to reach. Matched on the command, because
    // `listForNamespace` refuses an unreadable answer rather than reading it
    // as empty.
    when(() => mockRemote.executeCommand(any(that: startsWith('enroll:listns')),
        auth: any(named: 'auth'))).thenAnswer((_) async => 'data:[]');

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
      // NOTE: verify() throws when the mock was never called, which is what
      // the legacy arm expects; an empty list says it.
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
    expect(params['encryptedAPKAMSymmetricKey'], isNull,
        reason: 'a retrofit conveys nothing — the keyfile already holds every '
            'secret an approver would otherwise pass on — and the atServer '
            'approves this request outright rather than parking it pending, '
            'so there is no approval for a symmetric key to serve. It sent '
            'one until 2026-09-08, purely so the client could approve its own '
            'request against an atServer that parked it');
  });

  /// The control: the same keyfile, the same absence of an enrollment, only
  /// the posture differs.
  test('at a legacy posture the same client asks for nothing', () async {
    final commands = await commandsFromStartup('@bob', PqPosture.legacy);

    expect(commands.where((c) => c.startsWith('enroll:request:')), isEmpty,
        reason: 'legacy means "do not drive an upgrade"; a client that enrols '
            'here would be converting an atSign whose app asked it not to. '
            'Commands seen: $commands');
  });
}
