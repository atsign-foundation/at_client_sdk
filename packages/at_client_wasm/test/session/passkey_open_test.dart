import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_client_wasm/at_client_wasm.dart'
    show PortalSessionOfflineException;
import 'package:at_client_wasm/src/session/session_open.dart';
import 'package:test/test.dart';

import 'wire_fakes.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';

/// A sealer that keeps the plaintext: the vault's framing is under test
/// elsewhere, this test needs a store that round-trips. Records being closed.
class _Sealer implements RecordSealer {
  var closed = false;

  @override
  Future<Uint8List> seal(
          Uint8List iv, List<int> plaintext, List<int> aad) async =>
      Uint8List.fromList(plaintext);

  @override
  Future<Uint8List> open(
          Uint8List iv, Uint8List ciphertext, List<int> aad) async =>
      ciphertext;

  @override
  void close() => closed = true;
}

class _Docs implements EnrollmentDocumentStore {
  final records = <String, String>{};
  var gets = 0;

  @override
  Future<String?> get(String atSign, String enrollmentId) async {
    gets++;
    return records[enrollmentDocumentKey(enrollmentId, atSign)];
  }

  @override
  Future<void> put(String atSign, String enrollmentId, String document) async {
    records[enrollmentDocumentKey(enrollmentId, atSign)] = document;
  }

  @override
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
          {required Duration ttl}) async =>
      ServerMutexLease(
          AtKey.fromString(enrollmentLockKey(enrollmentId, atSign)),
          DateTime.now().add(ttl));
}

String _b(String s) => base64Encode(utf8.encode(s));

/// `openSession` on the key store a passkey enrollment really has: a document
/// with no APKAM private key, and the derived pair held by the store.
void main() {
  final finder = FixedSecondaryAddressFinder('atserver.test', 1);
  late Wire wire;
  late _Docs docs;
  late _Sealer sealer;
  late PasskeyVault vault;
  late ApkamKeyPair pair;

  PasskeyVault newVault() => PasskeyVault((
        lookupHex: '0' * 64,
        ns: '1' * 64,
        authSeed: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        sealer: sealer = _Sealer(),
      ), atSign: '@alice');

  /// The enrollment's key store, sealed with [vault].
  AtServerAtKeysIo newStore() => AtServerAtKeysIo(
      documents: docs,
      atSign: _atSign,
      seal: (d) => vault.seal(PasskeyRecordType.atkeys, d),
      open: (r) => vault.open(PasskeyRecordType.atkeys, r),
      enrollmentId: _eid,
      apkamKeyPair: pair);

  Future<AtClient> open(AtServerAtKeysIo keysIo) => openSession(
          lookUp: wire.lookUps(
              atSign: _atSign,
              rootDomain: AtRootDomain.atsignDomain,
              authenticator: null,
              secondaryAddressFinder: finder),
          atSign: _atSign,
          enrollmentId: _eid,
          keysIo: keysIo,
          app: 'wavi',
          transport: (
            lookUps: wire.lookUps,
            finder: finder,
            root: AtRootDomain.atsignDomain
          ));

  /// Whether [store] and [vault] are both still open: the store still serves
  /// the document's keys and holds its APKAM private key, and the vault still
  /// seals with an open sealer.
  Future<void> expectStillOpen(AtServerAtKeysIo store) async {
    expect(store.holdsPrivateKey, isTrue, reason: 'the store is not closed');
    await expectLater(Future.sync(() => store.read(_atSign)), completes,
        reason: 'the store is not closed');
    expect(sealer.closed, isFalse, reason: 'the vault is not closed');
    await expectLater(
        vault.seal(PasskeyRecordType.atkeys, {'probe': true}), completes,
        reason: 'the vault is not closed');
  }

  setUp(() async {
    wire = Wire()..runsAuthenticator = true;
    docs = _Docs();
    vault = newVault();
    pair = await vault.withAuthSeed(apkamKeyPairFromSeed);
    docs.records[enrollmentDocumentKey(_eid, _atSign)] =
        await vault.seal(PasskeyRecordType.atkeys, {
      ...(AtKeys.legacy(
              apkamPublicKey: _b('apkam-pub'),
              encryptionPublicKey: _b('enc-pub'),
              encryptionPrivateKey: _b('enc-priv'),
              selfEncryptionKey: _b('self-1'))
            ..atsign = _atSign.toAtsign())
          .toJson(),
      'version': AtKeys.supportedVersion,
      'atsign': _atSign,
      'keys': <Object?>[],
    });
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    vault.close();
  });

  test('opens as the enrollment and re-authenticates from the store', () async {
    final client = await open(newStore());

    expect(client.enrollmentId, _eid);
    final lookUp = wire.lookUpsBuilt.last;
    final gets = docs.gets;
    final commands = wire.pkamCommands.length;
    await lookUp.close();
    expect(await lookUp.pkamAuthenticate().timeout(const Duration(seconds: 5)),
        isTrue);
    expect(wire.pkamCommands.length, commands + 1);
    expect(wire.pkamCommands.last, contains('enrollmentId:$_eid:'));
    expect(docs.gets, gets, reason: 'PKAM reads the keys from memory');
  });

  group('the key store is lent to the client', () {
    test('stopping the client leaves the key store and the vault open',
        () async {
      final store = newStore();
      final client = await open(store);

      await client.stop();

      await expectStillOpen(store);
    });

    test(
        'a client that does not come online is stopped and leaves the key '
        'store and the vault open', () async {
      wire
        ..runsAuthenticator = false
        ..pkamAccepted = false;
      final store = newStore();

      await expectLater(
          open(store), throwsA(isA<PortalSessionOfflineException>()));

      expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);
      await expectStillOpen(store);
    });
  });
}
