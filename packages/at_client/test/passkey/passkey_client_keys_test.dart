import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/enrollment_pointer_store.dart'
    show enrollmentPointerKey;
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed, withApkamKey;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';
import '../support/passkey_at_server.dart';

const _atSign = '@alice🛠';
const _cram = 'cram-secret';
const _eid = 'e1d2c3';
const _root = AtRootDomain('root.test', 64);

void main() {
  late PasskeyAtServer server;
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

  AtAuthEnrollmentGateway gateway() => AtAuthEnrollmentGateway(
      lookUps: server.lookUps,
      finder: server.finder,
      root: _root,
      app: 'wavi',
      device: 'browser',
      clientOpener: openClient,
      activator: activate);

  PasskeyCustody custody(FakeHints hints) => PasskeyCustody(
      prf: PasskeyPrf(authenticator),
      deriver: const BytesPasskeyKeyDeriver(),
      pointerReader: LookupEnrollmentPointerReader(
          lookUps: server.lookUps,
          rootDomain: _root,
          secondaryAddressFinder: server.finder),
      gateway: gateway(),
      hints: hints,
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
    server = PasskeyAtServer(_atSign);
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

  test(
      'Two clients of one enrollment add key material at once, and both '
      'additions survive', () async {
    server.immutableHolds = true;
    final session = await onboard();
    final enrollmentId = session.client.enrollmentId!;
    final keys = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i)), _atSign);
    addTearDown(keys.vault.close);
    final pair = await apkamKeyPairFromSeed(keys.authSeed);
    final other = await gateway().authenticate(
        atSign: _atSign, enrollmentId: enrollmentId, apkamKeyPair: pair);
    addTearDown(other.close);
    final otherStore = AtServerAtKeysIo(
        documents: other.documents,
        atSign: _atSign,
        seal: (d) => keys.vault.seal(PasskeyRecordType.atkeys, d),
        open: (r) => keys.vault.open(PasskeyRecordType.atkeys, r),
        enrollmentId: enrollmentId,
        apkamKeyPair: pair);
    addTearDown(otherStore.close);
    server.holdDocumentPut = true;

    await Future.wait([
      (session.client.atKeysIo as WrittenAtKeysIo).update(_atSign.toAtsign(),
          (keys) {
        keys.fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: base64Encode(utf8.encode('one-pub')),
            privateKey: base64Encode(utf8.encode('one-priv')));
        return true;
      }),
      otherStore.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(
            apkamSymmetricKey: base64Encode(utf8.encode('two-sym')));
        return true;
      }),
    ]);

    final raw = jsonEncode(await documentOf(enrollmentId));
    expect(raw, contains(base64Encode(utf8.encode('one-priv'))));
    expect(raw, contains(base64Encode(utf8.encode('two-sym'))));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test("Every @keys write holds the enrollment's lock", () async {
    final onboarded = await onboard();
    final enrollmentId = onboarded.client.enrollmentId!;
    await onboarded.stop();
    // A session opened again runs on a store that holds no lease, so its
    // write cannot lean on the lock onboarding took.
    final session = await custody(FakeHints()).open(atSign: _atSign);
    sessions.add(session);
    final opened = server.commands.length;
    await (session.client.atKeysIo as WrittenAtKeysIo)
        .update(_atSign.toAtsign(), (keys) {
      keys.fileLegacyMaterial(
          apkamSymmetricKey: base64Encode(utf8.encode('sym')));
      return true;
    });

    String command(int i) =>
        server.commands[i].substring(server.commands[i].indexOf(': ') + 2);
    final lock = 'atkeys-lock.$enrollmentId.a.__e$_atSign ';
    final writes = [
      for (var i = 0; i < server.commands.length; i++)
        if (command(i).startsWith('update:atkeys.$enrollmentId.a.__e')) i
    ];
    expect(writes, hasLength(greaterThanOrEqualTo(2)),
        reason: 'the onboarding write and the client\'s');
    expect(writes.last, greaterThanOrEqualTo(opened),
        reason: 'the reopened client\'s write came after it opened');
    for (final (n, write) in writes.indexed) {
      // Each store's first write takes its own lock: only a take after the
      // write before it counts.
      final since = n == 0 ? 0 : writes[n - 1] + 1;
      final taken = [
        for (var i = since; i < write; i++)
          if (command(i).startsWith('update:') && command(i).contains(lock)) i
      ];
      expect(taken, isNotEmpty, reason: 'write $write took no lock of its own');
      expect(command(taken.last),
          startsWith('update:nc:ttl:10000:isEncrypted:false:immutable:true:'));
      // That the lease has half its ttl left when the document is put is
      // pinned with a clock this in-memory atServer has not got, in
      // passkey_keys_lock_test.dart.
    }
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
