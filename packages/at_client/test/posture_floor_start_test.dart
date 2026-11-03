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

  /// An atServer that holds nothing for this client, or fails every request
  /// when not [reachable].
  ({MockRemoteSecondary remote}) atServer({bool reachable = true}) {
    Future<String> answer(String reply) async {
      if (!reachable) {
        throw AtConnectException('the atServer cannot be reached');
      }
      return reply;
    }

    final lookUp = MockAtLookupImpl();
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) => answer('error:AT0011-Internal server exception'));
    when(() => lookUp.close()).thenAnswer((_) async {});
    final remote = MockRemoteSecondary();
    when(() => remote.atLookUp).thenReturn(lookUp);
    when(() => remote.executeVerb(any())).thenAnswer((invocation) => answer(
        invocation.positionalArguments.first is ScanVerbBuilder
            ? 'data:[]'
            : 'data:null'));
    when(() => remote.executeCommand(any(that: startsWith('enroll:fetch')),
        auth: any(named: 'auth'))).thenAnswer((_) async {
      if (!reachable) {
        throw AtConnectException('the atServer cannot be reached');
      }
      throw AtKeyNotFoundException('not held');
    });
    when(() => remote.executeCommand(any(that: startsWith('enroll:listns')),
        auth: any(named: 'auth'))).thenAnswer((_) => answer('data:[]'));
    return (remote: remote);
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

  /// An atServer on which `@alice` publishes no signing root and [enrollmentId]
  /// holds `*:rw` and `__manage:rw`, recording the key of every record
  /// written to it.
  ({MockRemoteSecondary remote, List<String> written}) rootlessAtServer() {
    final remote = atServer().remote;
    final written = <String>[];
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is ScanVerbBuilder) return 'data:[]';
      if (builder is UpdateVerbBuilder) {
        written.add(builder.atKey.key);
        return 'data:1';
      }
      throw AtKeyNotFoundException('not held');
    });
    when(() =>
        remote.executeCommand(any(that: startsWith('enroll:list')),
            auth: any(named: 'auth'))).thenAnswer((_) async => 'data:'
        '${jsonEncode({
              '$enrollmentId.new.enrollments.__manage$atSign': {
                'appName': 'buzz',
                'deviceName': 'test',
                'namespace': {'*': 'rw', '__manage': 'rw'},
                'status': 'approved',
              }
            })}');
    return (remote: remote, written: written);
  }

  /// [posture] with every startup step off but the one that mints the
  /// signing root.
  AtClientPreference rootStepOnly(PqPosture posture) => AtClientPreference(
      posture: posture,
      pqStartupGates: const PqStartupGates(
        hydrateHeldSecrets: false,
        collectConveyedKeys: false,
        startEnvelopeListener: false,
        mintInUseSigningKeys: false,
        refreshOwnLinks: false,
        reconcileKeyPackage: false,
        seedNamespaceKeys: false,
        requestRootPrivate: false,
        requestMissingPrivates: false,
        sweepUnanchoredEnrollments: false,
        reconcileEnrollmentSnapshot: false,
        askOnReadMiss: false,
      ));

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

  test('The floor holds at a start with no atServer', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');
    final server = atServer(reachable: false);

    final client = await start(configured(PqPosture.legacy), io, server.remote);

    expect(floorWarnings(), [contains('is raised to its pqReady floor')]);
    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue);
  });

  test('a raise names only the settings it changed', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');

    await start(
        AtClientPreference(
            posture: PqPosture.legacy,
            dataSigningKeyAlgorithms: {SigningAlgoType.rsa2048},
            pqStartupGates: const PqStartupGates.inert()),
        io,
        atServer().remote);

    expect(
        floorWarnings(),
        [
          allOf(contains('authenticationKeyAlgorithm mldsa65'),
              isNot(contains('dataSigningKeyAlgorithms')))
        ],
        reason: 'the data signing set is {rsa2048} before and after the raise');
  });

  test('A floor does not turn seeding on', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');

    final client =
        await start(configured(PqPosture.legacy), io, atServer().remote);

    final preference = client.getPreferences()!;
    expect(preference.posture.configuresPqProviders, isTrue,
        reason: 'it runs at its pqReady floor');
    expect(preference.seedNamespaceKeys, isFalse, reason: 'and seeds none');
    expect(preference.posture.seedNamespaceKeys, isFalse);
  });

  test('A floor does not mint a signing root', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');
    final server = rootlessAtServer();

    final client =
        await start(rootStepOnly(PqPosture.legacy), io, server.remote);
    await client.pqBootstrap!.startupComplete;

    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue,
        reason: 'it runs at its pqReady floor');
    expect(server.written, isNot(contains(PqSigningRoot.recordName)),
        reason: 'and publishes no signing root');
    expect(await client.pqBootstrap!.root.privateHalf(atSign), isNull);
  });

  test(
      'a client configured pqReady on the same keyfile mints the signing root '
      'its atSign lacks', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');
    final server = rootlessAtServer();

    final client =
        await start(rootStepOnly(PqPosture.pqReady), io, server.remote);
    await client.pqBootstrap!.startupComplete;

    expect(server.written, contains(PqSigningRoot.recordName),
        reason: 'the control: a start configured for post-quantum creates the '
            'root this harness offers, so its absence above is the floor');
  });

  test(
      'A client configured at or above its floor runs as configured, without '
      'a warning', () async {
    for (final posture in [PqPosture.pqReady, PqPosture.pqActive]) {
      logs.records.clear();
      final io = await keyfile();
      await holdNamespaceKey(io, 'k1.sensor');
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
    final preference = configured(PqPosture.legacy);

    final client = await start(preference, io, atServer().remote);

    expect(client.getPreferences(), same(preference));
    expect(floorWarnings(), isEmpty);
  });

  test(
      'A posture no named stage defines is raised only where it is below the '
      'floor', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');

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
    await holdNamespaceKey(io, 'k1.sensor');
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

  test('a raised client takes back the preference getPreferences returns',
      () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');
    final client =
        await start(configured(PqPosture.legacy), io, atServer().remote);

    client.setPreferences(client.getPreferences()!..syncBatchSize = 10);
    expect(client.getPreferences()!.syncBatchSize, 10);
    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue,
        reason: 'it still runs at its floor');

    final again = await AtClientImpl.create(
        atSign, 'buzz', client.getPreferences()!,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atKeysIo: io,
        enrollmentId: enrollmentId,
        storage: client.storage!);
    expect(again, same(client),
        reason: 'create reuses it given the preference it runs on');

    client.setPreferences(configured(PqPosture.legacy));
    expect(client.getPreferences()!.posture.configuresPqProviders, isTrue,
        reason: 'the preference it was configured with is still taken, and '
            'raised');
  });

  test(
      'a raised client refuses a preference naming a stage it neither was '
      'configured at nor runs at', () async {
    final io = await keyfile();
    await holdNamespaceKey(io, 'k1.sensor');
    final client =
        await start(configured(PqPosture.legacy), io, atServer().remote);

    expect(() => client.setPreferences(configured(PqPosture.pqActive)),
        throwsArgumentError);
    await expectLater(
        AtClientImpl.create(atSign, 'buzz', configured(PqPosture.pqActive),
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            atKeysIo: io,
            enrollmentId: enrollmentId,
            storage: client.storage!),
        throwsArgumentError);
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
