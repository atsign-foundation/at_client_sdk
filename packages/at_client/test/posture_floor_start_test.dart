import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_auth/at_auth.dart' show CryptographicMaterialAlgorithm;
import 'package:at_client/at_client_io.dart';
import 'package:at_client/at_client_mixins.dart' show EnrollmentUpdater;
import 'package:at_client/memory.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart'
    show PqStartupGates;
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';
import 'test_utils/transport.dart';

/// A client's start raises it to its posture floor: the higher of what its
/// enrollment's key material sets and what its atSign advertises.
///
/// Catalogue: features/at_client/posture_floor.feature
void main() {
  const atSign = '@alice';
  const enrollmentId = 'e-1';
  final logs = RecordedLogs();

  setUpAll(() {
    logs.installOn();
    registerFallbackValue(FakeLookupVerbBuilder());
  });

  setUp(logs.records.clear);

  /// An atServer whose scan for namespace keys answers [nskeys], or fails
  /// when not [reachable]; [scans] counts those scans and [commands] holds
  /// what the client sent on its lookup.
  ({MockRemoteSecondary remote, List<String> scans, List<String> commands})
      atServer(
          {List<String> nskeys = const [],
          bool reachable = true,
          Map<String, dynamic>? enrollment}) {
    final lookUp = MockAtLookupImpl();
    final commands = <String>[];
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      commands.add(invocation.positionalArguments.first as String);
      return 'error:AT0011-Internal server exception';
    });
    when(() => lookUp.close()).thenAnswer((_) async {});
    final remote = MockRemoteSecondary();
    when(() => remote.atLookUp).thenReturn(lookUp);
    final scans = <String>[];
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is ScanVerbBuilder && builder.regex == r'__nskey\.') {
        scans.add(builder.buildCommand());
        if (!reachable) {
          throw AtConnectException('the atServer cannot be reached');
        }
        return 'data:${jsonEncode(nskeys)}';
      }
      return builder is ScanVerbBuilder ? 'data:[]' : 'data:null';
    });
    when(() => remote.executeCommand(any(that: startsWith('enroll:fetch')),
        auth: any(named: 'auth'))).thenAnswer((_) async {
      if (enrollment == null) throw AtKeyNotFoundException('not held');
      return 'data:${jsonEncode(enrollment)}';
    });
    when(() => remote.executeCommand(any(that: startsWith('enroll:listns')),
        auth: any(named: 'auth'))).thenAnswer((_) async => 'data:[]');
    return (remote: remote, scans: scans, commands: commands);
  }

  /// A keyfile whose enrollment authenticates with [algorithm].
  Future<InMemoryAtKeysIo> keyfile(
          {CryptographicMaterialAlgorithm algorithm =
              CryptographicMaterialAlgorithm.mlDsa65}) =>
      typedKeyfile(atSign, enrollmentId: enrollmentId, algorithm: algorithm);

  Future<void> holdNamespaceKey(InMemoryAtKeysIo io, String namespace) async {
    final pair = await XWingKeyPair.generate();
    await NskeyPrivateFiling(keysIo: io, atSign: atSign).store(
        namespace: namespace,
        nskeyKid: nskeyKidOf(pair.publicKeyBytes),
        seed: NskeySeed(pair.privateKeyBytes));
  }

  Future<void> recordFloor(InMemoryAtKeysIo io) => io.update(atSign.toAtsign(),
      (keys) => keys.raiseAtSignFloor(AtKeys.atSignFloorPqReady));

  AtClientPreference configured(PqPosture posture) => AtClientPreference(
      posture: posture, pqStartupGates: const PqStartupGates.inert());

  Future<AtClientImpl> start(AtClientPreference preference, InMemoryAtKeysIo io,
      MockRemoteSecondary remote) async {
    AtClientImpl.atClientInstanceMap.removeWhere((key, _) =>
        key == atSign || (key is String && key.startsWith('$atSign|')));
    final client = await AtClientImpl.create(atSign, 'buzz', preference,
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            remoteSecondary: remote,
            atKeysIo: io,
            enrollmentId: enrollmentId,
            storage:
                InMemoryAtClientStorage(atSign: atSign, closedByClient: true))
        as AtClientImpl;
    addTearDown(client.stop);
    return client;
  }

  Iterable<String> floorWarnings() =>
      logs.at('WARNING').where((m) => m.contains('floor'));

  test(
      'A client whose keyfile holds a namespace-key private runs at pqReady '
      'at least', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');
    final server = atServer();

    final client = await start(configured(PqPosture.legacy), io, server.remote);

    expect(floorWarnings(), [
      contains(
          'is configured PqPosture.legacy and is raised to its pqReady floor')
    ]);
    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue);
    expect(
        CryptoConfig.forClient(client)
            .providers
            .any((provider) => provider.id == nskeyCryptoProviderId),
        isTrue,
        reason: 'it reads what is sealed to its namespace keys');
    expect(server.scans, isEmpty,
        reason: 'the key material already sets the floor, so nothing is read');
  });

  test(
      'A client whose keyfile holds an ML-DSA-65 client data signing key runs '
      'at pqActive', () async {
    final io = await keyfile();
    final pair = await MlDsa65PureDartAlgo().generateKeyPair();
    await io.update(atSign.toAtsign(), (keys) {
      keys.fileSigningMaterial(
          enrollmentId: enrollmentId,
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: base64Encode(pair.publicKey),
          privateKey: base64Encode(pair.secretKey));
      return true;
    });
    final server = atServer();

    final client =
        await start(configured(PqPosture.pqReady), io, server.remote);

    expect(floorWarnings(), [contains('is raised to its pqActive floor')]);
    expect(client.getPreferences()!.posture.writesPqByDefault, isTrue);
    expect(CryptoConfig.forClient(client).defaultProviderId,
        symmetricAesGcmCryptoProviderId,
        reason: 'it writes post-quantum by default');
    final reconciled = await SigningKeyMinting(client, updater: _Refusing())
        .reconcileSigningKeys();
    expect(reconciled.minted, isEmpty,
        reason: 'it mints no RSA-2048 client data signing key');
  });

  test(
      'A legacy client of an atSign that publishes a namespace key runs at '
      'pqReady', () async {
    // NOTE: flat, as an enrollment made at the legacy key exchange leaves it.
    final encryption = RsaKeyPair.generate();
    final pkam = RsaKeyPair.generate();
    final io = InMemoryAtKeysIo.holding(
        atSign,
        AtKeys(atsign: atSign.toAtsign())
          ..fileLegacyMaterial(
              apkamPublicKey: pkam.atPublicKey.publicKey,
              apkamPrivateKey: pkam.atPrivateKey.privateKey,
              encryptionPublicKey: encryption.atPublicKey.publicKey,
              encryptionPrivateKey: encryption.atPrivateKey.privateKey,
              selfEncryptionKey: AESKey.generate(32).key,
              enrollmentId: enrollmentId));
    final server = atServer(nskeys: [
      'public:__nskey.todos@alice'
    ], enrollment: {
      'appName': 'app',
      'deviceName': 'laptop',
      'namespace': {'todos': 'rw'},
      'status': 'approved',
    });

    await start(configured(PqPosture.legacy), io, server.remote);

    expect(floorWarnings(),
        [contains('is raised to its pqReady floor, set by its atSign')]);
    final request =
        server.commands.firstWhere((c) => c.startsWith('enroll:request:'),
            orElse: () => throw TestFailure('it did not re-enroll itself; '
                'commands seen: ${server.commands}'));
    final params = jsonDecode(request.substring('enroll:request:'.length))
        as Map<String, dynamic>;
    expect(params['signingAlgo'], SigningAlgoType.mldsa65.name,
        reason: 'it re-enrolls itself with ML-DSA-65 authentication');
    expect((await io.read(atSign)).atSignFloor, 'pqReady',
        reason: 'the floor is kept for a start with no atServer');
  });

  test("A peer's namespace key does not raise the floor", () async {
    final io = await keyfile();
    final server = atServer(nskeys: ['cached:public:__nskey.todos@bob']);

    final client = await start(configured(PqPosture.legacy), io, server.remote);

    expect(client.getPreferences()!.posture, same(PqPosture.legacy));
    expect(floorWarnings(), isEmpty);
    expect(server.scans, hasLength(1), reason: 'the control: it did look');
    expect((await io.read(atSign)).atSignFloor, isNull);
  });

  test('The floor an atSign set holds at a start with no atServer', () async {
    final io = await keyfile();
    await recordFloor(io);
    final server = atServer(reachable: false);

    final client = await start(configured(PqPosture.legacy), io, server.remote);

    expect(floorWarnings(), [contains('is raised to its pqReady floor')]);
    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue);
    expect(server.scans, isEmpty,
        reason: 'the keyfile already holds the floor, so nothing is read');
  });

  test('The floor never comes down', () async {
    final io = await keyfile();
    await recordFloor(io);
    final server = atServer(nskeys: const []);

    final client = await start(configured(PqPosture.legacy), io, server.remote);

    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue,
        reason: 'it runs at pqReady though the atSign publishes no namespace '
            'key now');
    expect((await io.read(atSign)).atSignFloor, 'pqReady');
  });

  test(
      'A client configured at or above its floor runs as configured, without '
      'a warning', () async {
    for (final posture in [PqPosture.pqReady, PqPosture.pqActive]) {
      logs.records.clear();
      final io = await keyfile();
      await recordFloor(io);
      final preference = configured(posture);

      final client = await start(preference, io, atServer().remote);

      expect(client.getPreferences(), same(preference),
          reason: 'it runs at ${postureOf(posture)} as configured');
      expect(floorWarnings(), isEmpty);
      await client.stop();
    }
  });

  test('A client with no floor runs as configured', () async {
    final io = await keyfile();
    final server = atServer(nskeys: const []);
    final preference = configured(PqPosture.legacy);

    final client = await start(preference, io, server.remote);

    expect(client.getPreferences(), same(preference));
    expect(floorWarnings(), isEmpty);
    expect(server.scans, hasLength(1),
        reason: 'the control: it read what its atSign advertises');
  });

  test(
      'A posture no named stage defines is raised only where it is below the '
      'floor', () async {
    final io = await keyfile();
    await recordFloor(io);

    final client = await start(
        AtClientPreference(
            posture: PqPosture.legacy.copyWith(mintLegacyMaterial: false),
            pqStartupGates: const PqStartupGates.inert()),
        io,
        atServer().remote);

    final posture = client.getPreferences()!.posture;
    expect(posture.configuresPqProviders, isTrue,
        reason: 'it reads post-quantum data as pqReady does');
    expect(client.getPreferences()!.authenticationKeyAlgorithm,
        SigningAlgoType.mldsa65);
    expect(posture.mintLegacyMaterial, isFalse,
        reason: 'and keeps mintLegacyMaterial false');
  });

  test(
      'a client raised to its floor takes its own preference again, and stays '
      'at the floor', () async {
    final io = await keyfile();
    await recordFloor(io);
    final preference = configured(PqPosture.legacy);
    final client = await start(preference, io, atServer().remote);

    final again = await AtClientImpl.create(atSign, 'buzz', preference,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atKeysIo: io,
        enrollmentId: enrollmentId,
        storage: client.storage!);
    expect(again, same(client),
        reason: 'the rollout axes are compared with what it was configured '
            'with, not with what the floor raised them to');

    client.setPreferences(configured(PqPosture.legacy)..namespace = 'other');
    expect(client.getPreferences()!.namespace, 'other');
    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue,
        reason: 'a preference set later is raised to the same floor');
  });
}

/// How a test names [posture].
String postureOf(PqPosture posture) =>
    identical(posture, PqPosture.pqActive) ? 'pqActive' : 'pqReady';

/// An enrollment updater no test here expects to be called.
class _Refusing implements EnrollmentUpdater {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('no update was expected: ${invocation.memberName}');
}
