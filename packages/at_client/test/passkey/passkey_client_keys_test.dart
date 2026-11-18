import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show withApkamKey;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';
import '../test_utils/fake_at_server.dart' show FakeAtServerSocket;

const _atSign = '@alice🛠';
const _cram = 'cram-secret';
const _eid = 'e1d2c3';
const _root = AtRootDomain('root.test', 64);

/// One atSign's atServer over in-memory sockets, with every connection run by
/// the production lookup: it answers `from:` with a fresh challenge, accepts
/// a `pkam:` only when its signature over that challenge verifies under the
/// APKAM public key of the enrollment it names, keeps what `update:` stores
/// and answers `llookup:`, `lookup:` and `delete:` from it.
class _AtServer implements AtTransportFactory {
  final records = <String, String>{};

  /// The APKAM public key of each enrollment.
  final apkamKeys = <String, String>{};

  /// Every command, as `<connection>: <command>`, connections counted from 0.
  final commands = <String>[];
  final sockets = <FakeAtServerSocket>[];
  final _challenges = <FakeAtServerSocket, String>{};
  final _authenticated = <FakeAtServerSocket>{};

  /// Whether the CRAM secret is still live, so an activation can use it.
  var cramLive = true;

  final SecondaryAddressFinder finder = _Here();

  AtLookUpFactory get lookUps => ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) =>
          AtLookUp.withSecureSocket(
              atSign: atSign,
              rootDomain: rootDomain,
              authenticator: authenticator,
              secondaryAddressFinder: finder,
              transport: AtLookupTransport(transportFactory: this));

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final socket = FakeAtServerSocket(_answer);
    sockets.add(socket);
    return socket;
  }

  /// The commands connection [connection] received, in order.
  List<String> on(int connection) => [
        for (final c in commands)
          if (c.startsWith('$connection: ')) c.substring('$connection: '.length)
      ];

  void _answer(FakeAtServerSocket socket, String command) {
    final line = command.trimRight();
    commands.add('${sockets.indexOf(socket)}: $line');
    unawaited(socket.serverSends(_reply(socket, line)));
  }

  String _reply(FakeAtServerSocket socket, String line) {
    final prompt = _authenticated.contains(socket) ? '\n$_atSign@' : '\n@';
    if (line.startsWith('from:')) {
      final challenge = '_${const Uuid().v4()}$_atSign:${const Uuid().v4()}';
      _challenges[socket] = challenge;
      return 'data:$challenge$prompt';
    }
    if (line.startsWith('pkam:')) {
      if (!_verifies(socket, line)) {
        return 'error:{"errorCode":"AT0401","errorDescription":"pkam '
            'authentication failed"}$prompt';
      }
      _authenticated.add(socket);
      return 'data:success\n$_atSign@';
    }
    if (line.startsWith('update:')) {
      final body = line.substring('update:'.length);
      final split = body.indexOf(' ');
      records[_keyOf(body.substring(0, split))] = body.substring(split + 1);
      return 'data:1$prompt';
    }
    if (line.startsWith('llookup:')) {
      return _value(records[line.substring('llookup:'.length)], prompt);
    }
    if (line.startsWith('lookup:')) {
      return _value(
          records['public:${line.substring('lookup:'.length)}'], prompt);
    }
    if (line.startsWith('delete:')) {
      if (line == 'delete:privatekey:at_secret') cramLive = false;
      records.remove(_keyOf(line.substring('delete:'.length)));
      return 'data:1$prompt';
    }
    if (line.startsWith('enroll:list')) return 'data:{}$prompt';
    if (line == 'stats:3') {
      return 'data:[{"id":"3","name":"lastCommitID","value":"-1"}]$prompt';
    }
    return 'data:null$prompt';
  }

  /// The key an `update:` or `delete:` names, without the metadata before it.
  static String _keyOf(String spec) {
    final public = spec.indexOf('public:');
    return public >= 0 ? spec.substring(public) : spec.split(':').last;
  }

  static String _value(String? value, String prompt) => value == null
      ? 'error:{"errorCode":"AT0015","errorDescription":"key not found"}'
          '$prompt'
      : 'data:$value$prompt';

  bool _verifies(FakeAtServerSocket socket, String line) {
    final enrollment =
        RegExp(r'enrollmentId:([^:]+):').firstMatch(line)?.group(1);
    final publicKey = apkamKeys[enrollment];
    final challenge = _challenges[socket];
    if (publicKey == null || challenge == null) return false;
    return MlDsa65PureDartAlgo.verifyBytesSync(
        Uint8List.fromList(utf8.encode(challenge)),
        signature: base64Decode(line.split(':').last),
        publicKey: base64Decode(publicKey));
  }
}

class _Here extends SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
}

void main() {
  late _AtServer server;
  late FakeAuthenticator authenticator;
  late List<PasskeySession> sessions;

  /// Activates [_atSign] as enrollment [_eid] with the passkey's pair, as an
  /// atServer's CRAM activation does: only while the CRAM secret is live.
  Future<AtKeys> activate(
      {required String atSign,
      required String cram,
      required ApkamKeyPair apkamKeyPair}) async {
    if (cram != _cram || !server.cramLive) {
      throw AtException('the CRAM secret is not live');
    }
    server.apkamKeys[_eid] = apkamKeyPair.publicKey;
    final keys = AtKeys.legacy(
        encryptionPublicKey: base64Encode(utf8.encode('enc-pub')),
        encryptionPrivateKey: base64Encode(utf8.encode('enc-priv')),
        selfEncryptionKey: AESKey.generate(32).key)
      ..atsign = atSign.toAtsign();
    return withApkamKey(keys, _eid, apkamKeyPair);
  }

  Future<AtClient> openClient(
          {required AtLookupMuxable lookUp,
          required String atSign,
          required String enrollmentId,
          required WrittenAtKeysIo keysIo}) =>
      Atsign(atSign).open(
          keys: keysIo,
          preference: AtClientPreference()
            ..namespace = 'wavi'
            ..rootDomain = _root.rootDomain
            ..rootPort = _root.rootPort
            ..remoteLocalPref = RemoteLocalPref.remoteOnly
            ..monitorAutoStart = false,
          namespace: 'wavi',
          storage:
              InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
          atLookUp: lookUp,
          lookUps: server.lookUps,
          secondaryAddressFinder: server.finder);

  PasskeyCustody custody(FakeHints hints) => PasskeyCustody(
      prf: PasskeyPrf(authenticator),
      deriver: const BytesPasskeyKeyDeriver(),
      pointerReader: LookupEnrollmentPointerReader(
          lookUps: server.lookUps,
          rootDomain: _root,
          secondaryAddressFinder: server.finder),
      gateway: AtAuthEnrollmentGateway(
          lookUps: server.lookUps,
          finder: server.finder,
          root: _root,
          app: 'wavi',
          device: 'browser',
          clientOpener: openClient,
          activator: activate),
      credentials: hints,
      enrollmentIds: hints,
      retryDelay: Duration.zero,
      setupLock: FakeSetupLock(),
      setupLockPrefix: 'test:setup');

  Future<PasskeySession> onboard() async {
    final session =
        await custody(FakeHints()).onboard(atSign: _atSign, cram: _cram);
    sessions.add(session);
    return session;
  }

  /// The enrollment id the passkey's pointer names.
  Future<String> pointedEnrollmentId() async {
    final keys = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i)), _atSign);
    addTearDown(keys.vault.close);
    final pointer = server.records[
        'public:${enrollmentPointerKey(_atSign, keys.lookupHex, ns: keys.ns)}']!;
    return (await keys.vault
        .open(PasskeyRecordType.eid, pointer))['enrollmentId'] as String;
  }

  /// The @keys document of [enrollmentId], opened with the passkey.
  Future<Map<String, dynamic>> documentOf(String enrollmentId) async {
    final keys = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i)), _atSign);
    addTearDown(keys.vault.close);
    return keys.vault.open(PasskeyRecordType.atkeys,
        server.records[enrollmentDocumentKey(enrollmentId, _atSign)]!);
  }

  setUp(() {
    server = _AtServer();
    authenticator = FakeAuthenticator();
    sessions = [];
  });

  tearDown(() async {
    for (final session in sessions) {
      await session.stop();
    }
  });

  test('Onboarding returns a client that is online as the new enrollment',
      () async {
    final session = await onboard();

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, await pointedEnrollmentId());
    expect(server.cramLive, isFalse);
  });

  test(
      'Logging in on a device that remembers nothing returns a client online '
      'as the pointed enrollment', () async {
    await (await onboard()).stop();
    sessions.clear();

    final session = await custody(FakeHints()).open(atSign: _atSign);
    sessions.add(session);

    expect(session.client.connection.current.isOnline, isTrue);
    expect(session.client.enrollmentId, await pointedEnrollmentId());
  });

  test('A passkey client re-authenticates after its connection drops',
      () async {
    final session = await onboard();
    final enrollmentId = session.client.enrollmentId!;
    final dropped = server.sockets.length - 1;
    expect(server.on(dropped), contains(startsWith('pkam:')),
        reason: 'the connection the client runs on');

    await server.sockets[dropped].serverCloses();
    await session.client
        .put(AtKey.self('note', namespace: 'wavi', sharedBy: _atSign).build(),
            'hello')
        .timeout(const Duration(seconds: 10));

    final reconnected = server.on(server.sockets.length - 1);
    final from = reconnected.indexWhere((c) => c.startsWith('from:'));
    final pkam = reconnected.indexWhere((c) => c.startsWith('pkam:'));
    final put = reconnected
        .indexWhere((c) => c.startsWith('update:') && c.contains('note.wavi'));
    expect(from, greaterThanOrEqualTo(0));
    expect(pkam, greaterThan(from));
    expect(reconnected[pkam], contains('enrollmentId:$enrollmentId:'));
    expect(put, greaterThan(pkam));
    expect(reconnected.sublist(from, pkam),
        everyElement(isNot(startsWith('llookup:atkeys.'))));
  });

  test('A @keys document a passkey client writes holds no APKAM private key',
      () async {
    final session = await onboard();
    final enrollmentId = session.client.enrollmentId!;
    final keysIo = session.client.atKeysIo as WrittenAtKeysIo;

    await keysIo.update(_atSign.toAtsign(), (keys) {
      keys.fileSigningMaterial(
          enrollmentId: enrollmentId,
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: base64Encode(utf8.encode('sign-pub')),
          privateKey: base64Encode(utf8.encode('sign-priv')));
      return true;
    });

    final document = await documentOf(enrollmentId);
    final raw = jsonEncode(document);
    expect(raw, contains(base64Encode(utf8.encode('sign-priv'))));
    expect(document, isNot(contains('aesPkamPrivateKey')));
    expect(raw, isNot(contains('"privateAuthentication"')));
  });
}
