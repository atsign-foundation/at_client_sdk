import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_client/at_client_mixins.dart' show pqNativeOnboard;
import 'package:at_client/passkey.dart' show AtAuthEnrollmentGateway;
import 'package:at_client/src/lifecycle/atsign_lifecycle.dart'
    show activateWithoutClient;
import 'package:at_client/src/preference/client_config.dart'
    show clientConfigOf;
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, RsaKeyPair, SHA512HashingAlgo;
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_utils.dart' show LoggingHandler, LogLevel;
import 'package:at_lookup/at_lookup.dart'
    show AtAuthenticator, AtCommandExecutor, SecondaryAddress;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/from_recorder.dart';
import '../test_utils/mocks.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/key_package_filing.dart';
import '../test_utils/transport.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// `Atsign.activate`: a CRAM activation writes the atSign's first keys to the
/// store named and opens a client on them.
///
/// The atServer is a mocked lookup answering by verb; supplying it skips the
/// provisioning wait, which polls a real atDirectory. Legacy activation only:
/// a post-quantum one mints a signing root through a live client, which the
/// live packs cover.
void main() {
  const atSign = '@newborn';
  const enrollmentId = 'first-1';
  const cramSecret = 'the-one-time-secret';
  late Directory dir;
  late _KeptLogs logs;
  late String rootLevel;
  late LoggingHandler handler;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    registerFallbackValue((AtCommandExecutor _) async => true);
    // NOTE: before any test; a logger binds its handler when it is made.
    rootLevel = AtSignLogger.root_level;
    handler = AtSignLogger.defaultLoggingHandler;
    logs = _KeptLogs(handler, LogLevel.level[rootLevel]);
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'finest';
  });

  tearDownAll(() {
    AtSignLogger.root_level = rootLevel;
    AtSignLogger.defaultLoggingHandler = handler;
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('activate_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<int> refusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<AtClientPreference> preference() async => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = await refusedPort()
    ..hiveStoragePath = dir.path
    ..namespace = 'lifecycle';

  /// An unactivated atServer: it accepts [cramSecret] and nothing else,
  /// approves the first enrollment on that connection, answers each PKAM
  /// attempt after it with [onPkam] (accepting it when null), and records
  /// every command and verb it was sent.
  ({MockAtLookupImpl lookUp, List<String> sent}) atServer(
      {Future<bool> Function()? onPkam}) {
    final lookUp = MockAtLookupImpl();
    final sent = <String>[];
    final installed = <AtAuthenticator?>[];
    when(() => lookUp.authenticator = any()).thenAnswer((invocation) {
      installed.add(invocation.positionalArguments.first as AtAuthenticator?);
      return null;
    });
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      sent.add(command);
      if (command.startsWith('lookup:publickey')) return 'data:null';
      if (command.startsWith('enroll:')) {
        return 'data:${jsonEncode({
              'enrollmentId': enrollmentId,
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
    // The first authenticator installed is the CRAM leg's, and it runs
    // against this atServer, which accepts the digest of cramSecret over its
    // challenge and nothing else; the PKAM legs after it are accepted.
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async =>
        installed.length == 1
            ? installed.single!(_CramAtServer(cramSecret))
            : onPkam == null || await onPkam());
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.dropConnection()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    when(() => lookUp.secondaryAddressFinder).thenReturn(_FoundAtDirectory());
    return (lookUp: lookUp, sent: sent);
  }

  test(
      'a legacy activation writes the first keys, completes, and opens an '
      'online client', () async {
    final store = InMemoryAtKeysIo();
    final server = atServer();
    final progress = <String>[];

    final client = await Atsign(atSign).activate(
        cramSecret: cramSecret,
        keys: store,
        preference: await preference(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        app: 'wavi',
        device: 'laptop',
        onProgress: (event) => progress.add(event.msg),
        atLookUp: server.lookUp,
        storage: hiveStoreFor(Atsign(atSign), await preference()));

    final keys = await store.read(atSign);
    expect(keys.holdsAuthenticationMaterial, isTrue);
    expect(keys.enrollmentToAuthenticateAs(), enrollmentId);
    // ignore: deprecated_member_use
    expect(keys.defaultEncryptionPrivateKey, isNotNull,
        reason: 'legacy material is minted by default');
    // ignore: deprecated_member_use
    expect(keys.defaultSelfEncryptionKey, isNotNull);

    expect(server.sent.where((c) => c.startsWith('enroll:')), hasLength(1));
    expect(server.sent.where((c) => c.startsWith('enroll:')).single,
        allOf(contains('"appName":"wavi"'), contains('"deviceName":"laptop"')),
        reason: 'the first enrollment is named as asked');
    expect(
        server.sent.any((c) =>
            c.startsWith('update:') && c.contains('public:publickey$atSign')),
        isTrue,
        reason: 'completion publishes the encryption public key');
    expect(
        server.sent.any((c) =>
            c.startsWith('delete:') && c.contains(AtConstants.atCramSecret)),
        isTrue,
        reason: 'and deletes the one-time secret from the atServer');

    expect(client.enrollmentId, enrollmentId);
    expect(client.connection.current.isOnline, isTrue);
    expect(progress, isNotEmpty, reason: 'the steps were narrated');
    await client.stop();
  });

  test(
      'pqNativeOnboard activates ML-DSA-65 whatever the preference says, '
      'and the manager adopts the client', () async {
    final store = InMemoryAtKeysIo();
    final server = atServer();
    final manager = AtClientManager(atSign);

    final adopted = await pqNativeOnboard(
        atSign: atSign,
        cramSecret: cramSecret,
        // A legacy posture, whose authentication algorithm is rsa2048: the
        // helper's whole point is to override it.
        preference: await preference(),
        atKeysIo: store,
        appName: 'wavi',
        deviceName: 'pq-native',
        manager: manager,
        storage: hiveStoreAt(atSign, dir.path),
        atLookUp: server.lookUp,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory());
    expect(adopted, same(manager));

    final keys = await store.read(atSign);
    expect(keys.signingAlgorithmForEnrollment(enrollmentId),
        SigningAlgoType.mldsa65);
    // ignore: deprecated_member_use
    expect(keys.apkamPublicKey, isNull,
        reason: 'a PQ-native keyfile keeps its APKAM in the typed section');
    expect(manager.atClient.enrollmentId, enrollmentId);
    expect(manager.atClient.connection.current.isOnline, isTrue);
    final enrollCommand =
        server.sent.where((c) => c.startsWith('enroll:')).single;
    expect(enrollCommand, contains('"signingAlgo":"mldsa65"'));
    expect(enrollCommand, contains('keyPackage'),
        reason: 'the request that creates the record carries the key package');
  });

  test('an activation files its first key package under its enrollment id',
      () async {
    final store = InMemoryAtKeysIo();
    final server = atServer();

    await pqNativeOnboard(
        atSign: atSign,
        cramSecret: cramSecret,
        preference: await preference(),
        atKeysIo: store,
        appName: 'wavi',
        deviceName: 'pq-native',
        manager: AtClientManager(atSign),
        storage: hiveStoreAt(atSign, dir.path),
        atLookUp: server.lookUp,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory());

    final request = server.sent.where((c) => c.startsWith('enroll:')).single;
    expectKeyPackageFiledUnder(await store.read(atSign), enrollmentId,
        kid: advertisedKid(request));
  });

  test(
      'an activation without a client and with completion deferred files the '
      'first keys, publishes no encryption public key and keeps the CRAM '
      'secret', () async {
    final store = InMemoryAtKeysIo();
    final server = atServer();

    final enrolled = await activateWithoutClient(Atsign(atSign),
        cramSecret: cramSecret,
        keys: store,
        preference: await preference(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atLookUp: server.lookUp,
        completeActivation: false,
        clientConfig: clientConfigOf(null));

    expect(enrolled, enrollmentId);
    expect(
        (await store.read(atSign)).enrollmentToAuthenticateAs(), enrollmentId);
    expect(server.sent.where((c) => c.contains('public:publickey$atSign')),
        isEmpty);
    expect(server.sent.where((c) => c.contains(AtConstants.atCramSecret)),
        isEmpty);
    expect(server.sent.where((c) => c.startsWith('enroll:')), hasLength(1));
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse);
  });

  test('an activation without a client leaves a supplied connection open',
      () async {
    final server = atServer();

    await activateWithoutClient(Atsign(atSign),
        cramSecret: cramSecret,
        keys: InMemoryAtKeysIo(),
        preference: await preference(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atLookUp: server.lookUp,
        completeActivation: false,
        clientConfig: clientConfigOf(null));

    verifyNever(() => server.lookUp.close());
  });

  test(
      'the passkey gateway activates with completion deferred: it publishes '
      'no encryption public key and keeps the CRAM secret', () async {
    final server = atServer();
    final gateway = AtAuthEnrollmentGateway(
        lookUps: (
                {required atSign,
                required rootDomain,
                required authenticator,
                secondaryAddressFinder}) =>
            server.lookUp,
        finder: await refusingAtDirectory(),
        root: AtRootDomain(
            InternetAddress.loopbackIPv4.address, await refusedPort()),
        app: 'lifecycle',
        device: 'gateway',
        clientOpener: (
                {required lookUp,
                required atSign,
                required enrollmentId,
                required keysIo}) =>
            throw StateError('the activation opens no client'));

    final session = await gateway.activate(
        atSign: atSign,
        apkamKeyPair: await apkamKeyPairFromSeed(
            Uint8List.fromList(List.generate(32, (i) => i + 7))),
        cram: cramSecret);

    expect(session.enrollmentId, enrollmentId);
    expect(server.sent.where((c) => c.startsWith('enroll:')), hasLength(1));
    expect(server.sent.where((c) => c.contains('public:publickey$atSign')),
        isEmpty,
        reason: 'the activation publishes no encryption public key');
    expect(
        server.sent.where((c) => c.contains(AtConstants.atCramSecret)), isEmpty,
        reason: 'the activation keeps the CRAM secret');
    await session.close();
  });

  test(
      "the passkey gateway's activation sends each from: naming at_client as "
      'the SDK, with its version', () async {
    final activation = atServer();
    final installed = <AtAuthenticator>[];
    when(() => activation.lookUp.authenticator = any()).thenAnswer((call) {
      final authenticator = call.positionalArguments.first as AtAuthenticator?;
      if (authenticator != null) installed.add(authenticator);
      return null;
    });
    // NOTE: each leg's from: is read as the leg runs, while the keys it reads
    // are the ones the activation holds at that moment.
    final froms = <String?>[];
    when(() => activation.lookUp.pkamAuthenticate()).thenAnswer((_) async {
      final authenticator = installed.last;
      final recorder = FromRecorder();
      await authenticator(recorder);
      froms.add(recorder.from);
      return froms.length == 1
          ? authenticator(_CramAtServer(cramSecret))
          : true;
    });
    final pkamLeg = atServer();
    when(() => pkamLeg.lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
    final connections = [activation.lookUp, pkamLeg.lookUp];
    var made = 0;
    final gateway = AtAuthEnrollmentGateway(
        lookUps: (
                {required atSign,
                required rootDomain,
                required authenticator,
                secondaryAddressFinder}) =>
            connections[made++],
        finder: await refusingAtDirectory(),
        root: AtRootDomain(
            InternetAddress.loopbackIPv4.address, await refusedPort()),
        app: 'lifecycle',
        device: 'gateway',
        clientOpener: (
                {required lookUp,
                required atSign,
                required enrollmentId,
                required keysIo}) =>
            throw StateError('the activation opens no client'));

    final session = await gateway.activate(
        atSign: atSign,
        apkamKeyPair: await apkamKeyPairFromSeed(
            Uint8List.fromList(List.generate(32, (i) => i + 7))),
        cram: cramSecret);
    addTearDown(session.close);

    expect(made, 2,
        reason: 'the control: one connection for the activation and one for '
            "the gateway's own PKAM");
    expect(froms, hasLength(2),
        reason: "the control: the CRAM login and the new keys' PKAM, both on "
            "the activation's connection");
    final atClientVersion = pubspecVersion();
    for (final from in froms) {
      const prefix = 'from:$atSign:clientConfig:';
      expect(from, startsWith(prefix));
      final config = jsonDecode(from!.substring(prefix.length).trim())
          as Map<String, dynamic>;
      expect(config['sdkName'], 'atsign.dart.at_client',
          reason: 'the activation names at_client as the SDK');
      expect(config['sdkVersion'], atClientVersion);
      expect(config['version'], atClientVersion);
    }
  });

  group('a supplied APKAM keypair', () {
    late ({String publicKey, String privateKey}) supplied;

    setUpAll(() {
      final pair = RsaKeyPair.generate();
      supplied = (
        publicKey: pair.atPublicKey.publicKey.toString(),
        privateKey: pair.atPrivateKey.privateKey.toString(),
      );
    });

    Future<AtClient> activateWith(
      InMemoryAtKeysIo store,
      ({MockAtLookupImpl lookUp, List<String> sent}) server, {
      ({String publicKey, String privateKey})? apkamKeyPair,
      SigningAlgoType? signingAlgo,
    }) async =>
        Atsign(atSign).activate(
          cramSecret: cramSecret,
          signingAlgo: signingAlgo,
          keys: store,
          preference: await preference(),
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: await refusingAtDirectory(),
          apkamKeyPair: apkamKeyPair,
          atLookUp: server.lookUp,
          storage: hiveStoreFor(Atsign(atSign), await preference()),
        );

    test('Atsign.activate passes the pair through and keeps it', () async {
      final store = InMemoryAtKeysIo();
      final server = atServer();

      await activateWith(store, server, apkamKeyPair: supplied);

      final enroll = server.sent.singleWhere((c) => c.startsWith('enroll:'));
      expect(enroll, contains('"apkamPublicKey":"${supplied.publicKey}"'));
      final keys = await store.read(atSign);
      // ignore: deprecated_member_use
      expect(keys.apkamPrivateKey.toString(), supplied.privateKey);
    });

    test('Atsign.activate refuses a mismatched pair before enrolling',
        () async {
      final store = InMemoryAtKeysIo();
      final server = atServer();
      final other = RsaKeyPair.generate();

      await expectLater(
        activateWith(
          store,
          server,
          apkamKeyPair: (
            publicKey: supplied.publicKey,
            privateKey: other.atPrivateKey.privateKey.toString(),
          ),
        ),
        throwsA(isA<AtSigningException>()),
      );
      expect(server.sent.where((c) => c.startsWith('enroll:')), isEmpty);
    });

    test(
        'Atsign.activate passes a supplied ML-DSA-65 pair through and keeps it',
        () async {
      final pair = await MlDsa65KeyPair.generate();
      final mldsa = (
        publicKey: pair.atPublicKey.publicKey,
        privateKey: pair.atPrivateKey.privateKey,
      );
      final store = InMemoryAtKeysIo();
      final server = atServer();

      await activateWith(store, server,
          apkamKeyPair: mldsa, signingAlgo: SigningAlgoType.mldsa65);

      final enroll = server.sent.singleWhere((c) => c.startsWith('enroll:'));
      expect(enroll, contains('"apkamPublicKey":"${mldsa.publicKey}"'));
      expect(enroll, contains('"signingAlgo":"mldsa65"'));
      final keys = await store.read(atSign);
      expect(
          keys
              .getKey(enrollmentId, 'auth:mldsa65:1',
                  CryptographicMaterialRole.privateAuthentication)!
              .bytes
              .toString(),
          mldsa.privateKey);
      expect(
          keys
              .getKey(enrollmentId, 'auth:mldsa65:1',
                  CryptographicMaterialRole.publicAuthentication)!
              .bytes
              .toString(),
          mldsa.publicKey);
    });

    test('Atsign.activate with no pair mints a fresh one', () async {
      final store = InMemoryAtKeysIo();
      final server = atServer();

      await activateWith(store, server);

      final enroll = server.sent.singleWhere((c) => c.startsWith('enroll:'));
      expect(enroll, isNot(contains(supplied.publicKey)));
      expect(enroll, contains('"apkamPublicKey"'));
    });
  });

  test('the provisioning wait ends when its budget is spent', () async {
    // No atLookUp: the activation polls the preference's atDirectory, which
    // refuses every connection, until the budget runs out.
    final started = DateTime.now();
    await expectLater(
        () async => Atsign(atSign).activate(
            cramSecret: cramSecret,
            keys: InMemoryAtKeysIo(),
            preference: await preference(),
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            provisioningBudget: const Duration(milliseconds: 600),
            provisioningPollInterval: const Duration(milliseconds: 100),
            storage: hiveStoreFor(Atsign(atSign), await preference())),
        throwsA(isA<AtTimeoutException>()));
    expect(DateTime.now().difference(started),
        lessThan(const Duration(seconds: 10)),
        reason: 'the budget bounds the wait; with none it is five minutes');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a wrong secret is refused and nothing is written', () async {
    final store = InMemoryAtKeysIo();
    final server = atServer();

    await expectLater(
        () async => Atsign(atSign).activate(
            cramSecret: 'not-it',
            keys: store,
            preference: await preference(),
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            atLookUp: server.lookUp,
            storage: hiveStoreFor(Atsign(atSign), await preference())),
        throwsA(isA<UnAuthenticatedException>().having((e) => e.message,
            'message', startsWith('Cram authentication failed for $atSign'))));
    await expectLater(
        () => store.read(atSign), throwsA(isA<AtKeysSourceAbsentException>()),
        reason: 'nothing was minted for a secret the atServer refused');
    expect(server.sent.where((c) => c.startsWith('enroll:')), isEmpty);
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse);
  });

  /// Catalogue: features/at_client/open_unusable_keys.feature
  test("An activation failure's message holds no stack trace", () async {
    final records = logs.keep();
    final server = atServer(
        onPkam: () async => throw UnAuthenticatedException(
            'Failed connecting to $atSign. error:{"errorCode":"AT0401",'
            '"errorDescription":"Exception: pkam authentication failed"}'));

    Object? thrown;
    try {
      await Atsign(atSign).activate(
          cramSecret: cramSecret,
          keys: InMemoryAtKeysIo(),
          preference: await preference(),
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: await refusingAtDirectory(),
          atLookUp: server.lookUp,
          storage: hiveStoreFor(Atsign(atSign), await preference()));
    } catch (e) {
      thrown = e;
    }

    expect(
        thrown,
        isA<AtException>()
            .having((e) => e.message, 'message',
                contains('pkam auth failed for $atSign'))
            .having(
                (e) => e.message,
                'stack trace',
                allOf(isNot(contains('\n')), isNot(contains('#0')),
                    isNot(contains('package:'))))
            .having((e) => '$e', 'text', isNot(contains('#0'))));
    final fine = records.where((r) =>
        '${r.level.name}' == 'FINE' &&
        '${r.message}'.contains('pkam auth failed for $atSign'));
    expect(fine, isNotEmpty, reason: 'the failure is logged at fine');
    expect(fine.first.stackTrace, isNotNull,
        reason: 'with its stack trace beside the message');
  });

  test(
      'Given an app named in its particulars, when Atsign.activate '
      'authenticates with CRAM and then PKAM, then each from: names the app '
      'and at_client', () async {
    final server = atServer();
    final named = (await preference())
      ..atClientParticulars.appName = 'acme_chat'
      ..atClientParticulars.appVersion = '2.3.1';

    final client = await Atsign(atSign).activate(
        cramSecret: cramSecret,
        keys: InMemoryAtKeysIo(),
        preference: named,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atLookUp: server.lookUp,
        storage: hiveStoreFor(Atsign(atSign), named));
    addTearDown(client.stop);

    final installed = verify(() => server.lookUp.authenticator = captureAny())
        .captured
        .whereType<AtAuthenticator>()
        .toList();
    expect(installed.length, greaterThanOrEqualTo(3),
        reason: 'the control: the CRAM login, the new keys, and the new keys '
            'again once the atServer names the enrollment');
    final atClientVersion = pubspecVersion();
    for (final authenticator in installed) {
      final recorder = FromRecorder();
      await authenticator(recorder);
      const prefix = 'from:$atSign:clientConfig:';
      expect(recorder.from, startsWith(prefix));
      final config = jsonDecode(recorder.from!.substring(prefix.length).trim())
          as Map<String, dynamic>;
      expect(config['appName'], 'acme_chat');
      expect(config['appVersion'], '2.3.1');
      expect(config['sdkName'], 'atsign.dart.at_client');
      expect(config['sdkVersion'], atClientVersion);
      expect(config['version'], atClientVersion);
    }
  });
}

/// The logging handler of every AtSignLogger this file makes: it passes each
/// record at or above [passOnFrom] on to [passOn], and keeps every record
/// while a test that called [keep] runs.
class _KeptLogs implements LoggingHandler {
  _KeptLogs(this.passOn, this.passOnFrom);

  final LoggingHandler passOn;

  /// The least level passed on; null passes every record on.
  final dynamic passOnFrom;

  List<dynamic>? _kept;

  /// The records logged from now until the calling test ends.
  List<dynamic> keep() {
    final kept = <dynamic>[];
    _kept = kept;
    addTearDown(() => _kept = null);
    return kept;
  }

  @override
  void call(dynamic record) {
    _kept?.add(record);
    if (passOnFrom == null || record.level >= passOnFrom) passOn(record);
  }
}

/// An atDirectory that finds every atSign.
class _FoundAtDirectory implements SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('localhost', 1);
}

/// Answers `from:` with a challenge, and `cram:` with success only for the
/// digest of [secret] over that challenge.
class _CramAtServer implements AtCommandExecutor {
  static const _challenge = 'challenge-for-the-test';
  final String secret;

  _CramAtServer(this.secret);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    if (command.startsWith('from:')) return 'data:$_challenge';
    final expected =
        SHA512HashingAlgo().hash(utf8.encode('$secret$_challenge'));
    return command.trim() == 'cram:$expected'
        ? 'data:success'
        : 'error:AT0401-Exception: the CRAM digest did not match';
  }
}
