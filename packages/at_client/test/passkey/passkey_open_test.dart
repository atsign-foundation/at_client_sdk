import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:test/test.dart';

import '../support/custody_fakes.dart';
import '../support/wire_fakes.dart';
import '../test_utils/transport.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';

/// Documents by key, counting every read, with no atServer in between.
class _Docs implements EnrollmentDocumentStore {
  final records = <String, String>{};
  var gets = 0;

  /// Reads the PKAM count at each get; a get after PKAM started is the
  /// self-deadlock (a document read under the PKAM mutex).
  int Function() pkamCount = () => 0;
  var getsAfterPkam = 0;

  @override
  Future<String?> get(String atSign, String enrollmentId) async {
    gets++;
    if (pkamCount() > 0) getsAfterPkam++;
    return records[enrollmentDocumentKey(enrollmentId, atSign)];
  }

  @override
  Future<void> put(String atSign, String enrollmentId, String document) async {
    records[enrollmentDocumentKey(enrollmentId, atSign)] = document;
  }

  @override
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
          {required Duration ttl}) async =>
      freeLease(atSign, enrollmentId, ttl);
}

void _fileSigning(AtKeys keys, String tag, {String eid = _eid}) =>
    keys.fileSigningMaterial(
        enrollmentId: eid,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        publicKey: _b('$tag-pub'),
        privateKey: _b('$tag-priv'));

String _b(String s) => base64Encode(utf8.encode(s));

/// The keys a passkey custody stores: everything but the APKAM private key.
AtKeys _stripped() => AtKeys.legacy(
    apkamPublicKey: _b('apkam-pub'),
    encryptionPublicKey: _b('enc-pub'),
    encryptionPrivateKey: _b('enc-priv'),
    selfEncryptionKey: _b('self-1'))
  ..atsign = _atSign.toAtsign();

/// `Atsign.open` on a passkey enrollment: the key store holds a document with
/// no APKAM private key, and the derived pair lives in the store.
void main() {
  late _Docs docs;
  late DerivedKeys derived;
  late ApkamKeyPair pair;
  late Wire wire;

  Future<AtServerAtKeysIo> store({AtKeys? restored}) async {
    docs.records[enrollmentDocumentKey(_eid, _atSign)] ??=
        await derived.vault.seal(PasskeyRecordType.atkeys, {
      ..._stripped().toJson(),
      'version': AtKeys.supportedVersion,
      'atsign': _atSign,
      'keys': <Object?>[],
    });
    return AtServerAtKeysIo(
        documents: docs,
        atSign: _atSign,
        seal: (d) => derived.vault.seal(PasskeyRecordType.atkeys, d),
        open: (r) => derived.vault.open(PasskeyRecordType.atkeys, r),
        enrollmentId: _eid,
        apkamKeyPair: pair,
        restored: restored);
  }

  Future<AtKeys> storedDocument() async =>
      AtKeys.fromJson(await derived.vault.open(PasskeyRecordType.atkeys,
          docs.records[enrollmentDocumentKey(_eid, _atSign)]!));

  void expectNoApkamPrivateMaterial(AtKeys doc, String raw) {
    // ignore: deprecated_member_use
    expect(doc.apkamPrivateKey, isNull);
    expect(doc.holdsAuthenticationMaterial, isFalse);
    expect(raw, isNot(contains(pair.privateKey)));
    expect(raw, isNot(contains(pair.publicKey)),
        reason: 'the overlay public half is stripped too');
  }

  Future<String> rawDocument() async => jsonEncode(await derived.vault.open(
      PasskeyRecordType.atkeys,
      docs.records[enrollmentDocumentKey(_eid, _atSign)]!));

  Future<AtClientImpl> open(AtServerAtKeysIo io) async =>
      await Atsign(_atSign).open(
          keys: io,
          preference: AtClientPreference()
            ..namespace = 'wavi'
            ..monitorAutoStart = false
            ..rootDomain = 'test.atsign.wtf',
          storage: InMemoryAtClientStorage(atSign: _atSign),
          lookUps: wire.lookUps,
          secondaryAddressFinder: defaultAtDirectory) as AtClientImpl;

  setUp(() async {
    docs = _Docs();
    wire = Wire()..runsAuthenticator = true;
    docs.pkamCount = () => wire.pkamCommands.length;
    derived = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
    pair = await derived.vault.withAuthSeed(apkamKeyPairFromSeed);
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      try {
        await c.stop();
      } catch (_) {
        // Teardown: a client the test already stopped may fail again.
      }
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  group('T1 Atsign.open on a stripped document', () {
    test('onboard and resume: the store reads the document', () async {
      final client = await open(await store());
      expect(client.connection.current.isOnline, isTrue);
      expect(client.enrollmentId, _eid);
      expect(docs.getsAfterPkam, 0, reason: 'no document read under PKAM');
    });

    test('login: the store is seeded with the restored keys', () async {
      final client = await open(await store(restored: _stripped()));
      expect(client.connection.current.isOnline, isTrue);
      expect(client.enrollmentId, _eid);
    });
  });

  group('T4 recovery of a stranded atSign', () {
    test('a published document: login opens a client', () async {
      final restored = await (await store()).read(_atSign);
      final client = await open(await store(restored: restored));
      expect(client.connection.current.isOnline, isTrue);
      expect(client.enrollmentId, _eid);
      expect(docs.getsAfterPkam, 0);
    });
  });

  group('T2 re-authentication', () {
    test('a forced reconnect signs with the derived pair and reads nothing',
        () async {
      final client = await open(await store());
      final lookUp = wire.lookUpsBuilt.last;
      final getsBefore = docs.gets;
      final commandsBefore = wire.pkamCommands.length;

      await lookUp.close();
      expect(await lookUp.pkamAuthenticate().timeout(Duration(seconds: 5)),
          isTrue);

      expect(wire.pkamCommands.length, commandsBefore + 1);
      expect(docs.gets, getsBefore,
          reason: 'PKAM reads the keys from memory, never the atServer');
      final command = wire.pkamCommands.last;
      expect(command, contains('enrollmentId:$_eid:'));
      final signature = base64Decode(command.trim().split(':').last);
      final challenge = utf8.encode('_123e4567-e89b-12d3-a456-426614174000'
          '$_atSign:123e4567-e89b-12d3-a456-426614174000');
      expect(
          MlDsa65PureDartAlgo.verifyBytesSync(Uint8List.fromList(challenge),
              signature: Uint8List.fromList(signature),
              publicKey: Uint8List.fromList(base64Decode(pair.publicKey))),
          isTrue);
      expect(client.enrollmentId, _eid);
    });
  });

  group('T3 the stored document never holds APKAM private material', () {
    test('write, flush and update strip the overlay', () async {
      final io = await store();
      await io.update(Atsign(_atSign), (keys) {
        _fileSigning(keys, 'sign-2');
        return true;
      });
      expectNoApkamPrivateMaterial(await storedDocument(), await rawDocument());

      final read = await io.read(_atSign);
      expect(read.holdsAuthenticationMaterial, isTrue);
      expect(read.enrollmentToAuthenticateAs(), _eid);
      _fileSigning(read, 'sign-3', eid: 'e9z9z9');
      await io.flush(Atsign(_atSign), read);
      expectNoApkamPrivateMaterial(await storedDocument(), await rawDocument());
      expect(await rawDocument(), contains(_b('sign-3')));
    });

    test('a first write of keys carrying the flat key strips it', () async {
      final io = AtServerAtKeysIo(
          documents: docs,
          atSign: _atSign,
          seal: (d) => derived.vault.seal(PasskeyRecordType.atkeys, d),
          open: (r) => derived.vault.open(PasskeyRecordType.atkeys, r),
          enrollmentId: _eid,
          apkamKeyPair: pair);
      final keys = _stripped()
        ..fileLegacyMaterial(apkamPrivateKey: pair.privateKey);
      await io.write(_atSign, keys);
      expectNoApkamPrivateMaterial(await storedDocument(), await rawDocument());
    });
  });

  group('T8 foreign private authentication material', () {
    test('a flush carrying another private auth key is refused', () async {
      final io = await store();
      await io.read(_atSign);
      final keys = _stripped();
      keys.fileApkamMaterial(
          enrollmentId: 'e9z9z9',
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: _b('other-pub'),
          privateKey: _b('other-priv'));
      final before = docs.records.values.single;
      await expectLater(io.flush(Atsign(_atSign), keys),
          throwsA(isA<AtServerAtKeysWriteException>()));
      expect(docs.records.values.single, before);
      await expectLater(io.flush(Atsign(_atSign), await io.read(_atSign)),
          throwsA(isA<AtServerAtKeysWriteException>()),
          reason: 'the store accepts no more writes after a refusal');
    });

    test('a flat private key that is not the pair is refused', () async {
      final io = await store();
      final keys = await io.read(_atSign)
        ..fileLegacyMaterial(apkamPrivateKey: _b('other-flat'));
      await expectLater(io.flush(Atsign(_atSign), keys),
          throwsA(isA<AtServerAtKeysWriteException>()));
    });
  });

  group('C1 and C5 reads', () {
    test('once open, read does no I/O and returns fresh copies', () async {
      final io = await store();
      await io.read(_atSign);
      final gets = docs.gets;
      final a = await io.read(_atSign);
      _fileSigning(a, 'mutated', eid: 'e9z9z9');
      final b = await io.read(_atSign);
      expect(docs.gets, gets);
      expect(jsonEncode(b.toJson()), isNot(contains(_b('mutated-priv'))));
    });

    test('a read after close throws StateError and the pair is gone', () async {
      final io = await store();
      await io.read(_atSign);
      io.close();
      await expectLater(io.read(_atSign), throwsA(isA<StateError>()));
    });
  });

  group('readers that could export what a read returns', () {
    // A read result holds the derived APKAM private key, so only audited files
    // may serialise AtKeys. A new one must be audited and listed here.
    test('only the audited files serialise a keys value', () {
      const audited = {
        'lib/src/lifecycle/pending_enrollment.dart',
        'lib/src/passkey/at_keys_document.dart',
        'lib/src/passkey/at_server_at_keys_io.dart',
        'lib/src/passkey/passkey_custody.dart',
        'at_auth/lib/src/keys/io/file_io.dart',
        'at_auth/lib/src/keys/io/memory_io.dart',
      };
      final serialises =
          RegExp(r'([kK]eys|stored|held|existing|restored|retrofitted|snapshot)'
              r'\w*\)?\.toJson\(\)');
      final found = <String>{};
      for (final root in ['lib', '../at_auth/lib']) {
        for (final f in Directory(root).listSync(recursive: true)) {
          if (f is File &&
              f.path.endsWith('.dart') &&
              serialises.hasMatch(f.readAsStringSync())) {
            found.add(f.path.replaceFirst('../', ''));
          }
        }
      }
      expect(found.difference(audited), isEmpty,
          reason: 'every file that serialises a keys value is audited');
      expect(audited.difference(found),
          anyOf(isEmpty, equals({'at_auth/lib/src/keys/io/memory_io.dart'})),
          reason: 'every audited file but the in-memory store serialises a '
              'keys value');
      for (final path in audited) {
        final local = path.startsWith('at_auth/') ? '../$path' : path;
        expect(File(local).existsSync(), isTrue,
            reason: 'every audited file exists: $path');
      }
    });
  });
}
