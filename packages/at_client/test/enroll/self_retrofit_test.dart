import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show selfRetrofit;
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// `selfRetrofit`: the successor is filed in the keyfile and the client
/// handed back opens on it, as the successor; nothing else is touched.
///
/// The atServer is a mocked lookup answering by verb, which also serves as
/// the client's connection.
void main() {
  const atSign = '@alice🛠';
  const legacyId = 'first-1';
  const newId = 'retro-2';
  late Directory dir;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('self_retrofit_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  /// A pre-retrofit keyfile: rsa2048 in the flat fields, enrolled as
  /// [legacyId].
  AtKeys legacyKeys() => AtKeys()
    // ignore: deprecated_member_use
    ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(demo.encryptionPrivateKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultSelfEncryptionKey = AtBytes.fromString(demo.aesKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..enrollmentId = legacyId;

  /// An atServer that auto-approves the self-enrollment as [newId], shows an
  /// empty roster, and records every command it was sent.
  ({MockAtLookupImpl lookUp, List<String> sent}) atServer() {
    final lookUp = MockAtLookupImpl();
    final sent = <String>[];
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      sent.add(command);
      if (command.startsWith('enroll:list')) return 'data:[]';
      if (command.startsWith('enroll:')) {
        return 'data:${jsonEncode({
              'enrollmentId': newId,
              'status': 'approved'
            })}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first as VerbBuilder;
      sent.add(builder.buildCommand());
      if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
        return 'data:1';
      }
      throw StateError('the mocked atServer has no answer for: '
          '${builder.buildCommand()}');
    });
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => true);
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    return (lookUp: lookUp, sent: sent);
  }

  test('files the successor and opens the client as it', () async {
    final store = InMemoryAtKeysIo.holding(atSign, legacyKeys());
    final server = atServer();

    final client = await selfRetrofit(
        session: AtAuthSession(
            atSign: atSign,
            rootDomain: const AtRootDomain('127.0.0.1', 1),
            atKeysIo: store,
            namespace: 'lifecycle',
            enrollmentId: legacyId),
        preference: AtClientPreference()
          ..hiveStoragePath = dir.path
          ..namespace = 'lifecycle',
        appName: 'wavi',
        deviceName: 'laptop',
        namespaces: const {'wavi': 'rw'},
        signingAlgo: SigningAlgoType.mldsa65,
        atLookUp: server.lookUp);

    expect(client.enrollmentId, newId,
        reason: 'the client runs as the enrollment the retrofit filed');
    expect(client.connection.current.isOnline, isTrue);
    final keys = await store.read(atSign);
    expect(keys.enrollmentToAuthenticateAs(), newId);
    expect(keys.signingAlgorithmForEnrollment(newId), SigningAlgoType.mldsa65);
    final submitted = server.sent
        .where((c) => c.startsWith('enroll:') && !c.startsWith('enroll:list'))
        .single;
    expect(
        submitted,
        allOf(
            contains('"appName":"wavi"'), contains('"signingAlgo":"mldsa65"')));
    expect(AtClientImpl.holdsLiveClientAs(atSign, legacyId), isFalse,
        reason: 'no legacy client was live, and none is built for it');

    await client.stop();
  });
}
