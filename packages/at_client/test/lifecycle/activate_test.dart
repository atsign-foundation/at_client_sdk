import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show pqNativeOnboard;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

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

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
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
  /// approves the first enrollment on that connection, and records every
  /// command and verb it was sent.
  ({MockAtLookupImpl lookUp, List<String> sent}) atServer() {
    final lookUp = MockAtLookupImpl();
    final sent = <String>[];
    when(() => lookUp.cramAuthenticate(any())).thenAnswer((invocation) async =>
        invocation.positionalArguments.first == cramSecret);
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      sent.add(command);
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
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => true);
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
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
        app: 'wavi',
        device: 'laptop',
        onProgress: (event) => progress.add(event.msg),
        atLookUp: server.lookUp);

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
        atLookUp: server.lookUp);
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

  test('the provisioning wait ends when its budget is spent', () async {
    // No atLookUp: the activation polls the preference's atDirectory, which
    // refuses every connection, until the budget runs out.
    final started = DateTime.now();
    await expectLater(
        () async => Atsign(atSign).activate(
            cramSecret: cramSecret,
            keys: InMemoryAtKeysIo(),
            preference: await preference(),
            provisioningBudget: const Duration(milliseconds: 600),
            provisioningPollInterval: const Duration(milliseconds: 100)),
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
            atLookUp: server.lookUp),
        throwsA(isA<AtAuthenticationException>()));
    await expectLater(
        () => store.read(atSign), throwsA(isA<AtKeysSourceAbsentException>()),
        reason: 'nothing was minted for a secret the atServer refused');
    expect(server.sent.where((c) => c.startsWith('enroll:')), isEmpty);
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse);
  });
}
