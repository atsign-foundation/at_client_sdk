import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show selfRetrofit;
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
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
    registerFallbackValue((AtCommandExecutor _) async => true);
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
    // NOTE: a client that retrofits as it opens links its legacy key to its
    // new one here, and a link left behind makes a later test's legacy key
    // resolve to that test's client.
    AtClientImpl.supersededInstanceKeys.clear();
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
  /// empty roster, answers `enroll:fetch` with [record] when given one, and
  /// records every command it was sent, each completed PKAM as
  /// `pkam:<the enrollment its pkam: command named>`, and each `close()`.
  ({MockAtLookupImpl lookUp, List<String> sent}) atServer(
      {Map<String, dynamic>? record}) {
    final lookUp = MockAtLookupImpl();
    final sent = <String>[];
    AtAuthenticator? installed;
    when(() => lookUp.authenticator = any()).thenAnswer((invocation) {
      installed = invocation.positionalArguments.first as AtAuthenticator?;
      return null;
    });
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      sent.add(command);
      if (command.startsWith('enroll:list')) return 'data:[]';
      if (record != null && command.startsWith('enroll:fetch')) {
        return 'data:${jsonEncode(record)}';
      }
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
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async {
      // NOTE: a round trip, as an atServer's challenge is, recorded once it
      // completes, so an attempt that gives up before then is seen not to
      // have authenticated.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final wire = _PkamAtServer();
      if (installed != null) await installed!(wire);
      sent.add('pkam:${wire.enrollmentId}');
      return true;
    });
    when(() => lookUp.close()).thenAnswer((_) async => sent.add('close()'));
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

  test("A client retrofitted on a caller's lookup logs in again", () async {
    final server = atServer();

    final client = await selfRetrofit(
        session: AtAuthSession(
            atSign: atSign,
            rootDomain: const AtRootDomain('127.0.0.1', 1),
            atKeysIo: InMemoryAtKeysIo.holding(atSign, legacyKeys()),
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

    final submitted = server.sent.indexWhere(
        (c) => c.startsWith('enroll:') && !c.startsWith('enroll:list'));
    expect(submitted, isNonNegative,
        reason: 'the premise: the retrofit was submitted on the given lookup');
    expect(
        server.sent
            .skip(submitted + 1)
            .where((c) => c != 'close()' && !c.startsWith('pkam:')),
        isNotEmpty,
        reason: 'the premise: the client ran a command on the lookup it took '
            'over');
    expect(server.sent.indexOf('close()'), submitted + 1,
        reason: 'the connection the submission logged in on closes before the '
            'client runs anything on it');
    expect(server.sent.skip(submitted + 1).where((c) => c != 'close()').first,
        'pkam:$newId',
        reason: 'the client has authenticated as the new enrollment before it '
            'runs anything on the lookup it took over');

    await client.stop();
  });

  test("A superseded enrollment's lookup cannot reconnect after a retrofit",
      () async {
    final servers = <({MockAtLookupImpl lookUp, List<String> sent})>[];

    final client = await Atsign(atSign).open(
        keys: InMemoryAtKeysIo.holding(atSign, legacyKeys()),
        preference: AtClientPreference(
            authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
            dataSigningKeyAlgorithms: {SigningAlgoType.mldsa65})
          ..hiveStoragePath = dir.path
          ..namespace = 'lifecycle',
        lookUps: (
            {required atSign,
            required rootDomain,
            required authenticator,
            secondaryAddressFinder,
            clientConfig = const {}}) {
          final server = atServer(record: {
            'appName': 'wavi',
            'deviceName': 'laptop',
            'namespace': {'wavi': 'rw'},
            'status': 'approved'
          });
          servers.add(server);
          return server.lookUp;
        });

    expect(client.enrollmentId, newId,
        reason: 'the premise: the client retrofitted as it opened');
    final superseded = servers
        .where((s) => s.sent.any((c) => c.startsWith('enroll:request')))
        .single
        .lookUp;
    expect(client.getRemoteSecondary()!.atLookUp, isNot(same(superseded)),
        reason: 'the premise: the client rederived its connection');
    verify(superseded.stop).called(1);
    verifyNever(superseded.close);

    await client.stop();
  });
}

/// Answers an authenticator's `from:` with a challenge for `@alice🛠` and its
/// `pkam:` with success, keeping the enrollment that `pkam:` named.
class _PkamAtServer implements AtCommandExecutor {
  String? enrollmentId;

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    if (command.startsWith('from:')) {
      return 'data:_70ce5d4e-1b8e-4a7c-9d1e-7e6c2a9b8f10@alice🛠'
          ':4f3c2b1a-9e8d-4c7b-a6f5-e4d3c2b1a098';
    }
    enrollmentId =
        RegExp(r'^pkam:.*:enrollmentId:([^:]+):').firstMatch(command)?[1];
    return 'data:success';
  }
}
