import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../support/custody_fakes.dart';
import '../support/lookup_fakes.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';

String _b(String s) => base64Encode(utf8.encode(s));

/// An atServer holding documents by key. It grants every create of a
/// document's lock.
class _DocumentServer {
  final records = <String, String>{};

  Future<String?> respond(String command) async {
    final line = command.substring(0, command.length - 1);
    if (line.startsWith('llookup:')) {
      final value = records[line.substring('llookup:'.length)];
      if (value == null) throw AtLookUpException('AT0015', 'key not found');
      return 'data:$value';
    }
    if (line.startsWith('update:') && line.contains('atkeys-lock.')) {
      return 'data:-1';
    }
    if (line.startsWith('update:')) {
      final body = line.substring('update:'.length);
      final split = body.indexOf(' ');
      records[body.substring(0, split)] = body.substring(split + 1);
      return 'data:1';
    }
    throw StateError('unexpected command $command');
  }
}

/// The update contract every `WrittenAtKeysIo` keeps: a change that returns
/// false or throws leaves the store as it was, whatever it did to the keys it
/// was handed, and one that returns true is stored.
void main() {
  late _DocumentServer server;
  late DerivedKeys derived;
  late ApkamKeyPair pair;
  final alice = _atSign.toAtsign();

  AtServerAtKeysIo open() => AtServerAtKeysIo(
      documents: RemoteEnrollmentDocumentStore(RemoteSecondary(
          _atSign, AtClientPreference(),
          atLookUp: ScriptedAtLookUp(server.respond),
          lookUps: RecordingLookUps((_) async => null).call)),
      atSign: _atSign,
      seal: (d) => derived.vault.seal(PasskeyRecordType.atkeys, d),
      open: (r) => derived.vault.open(PasskeyRecordType.atkeys, r),
      enrollmentId: _eid,
      apkamKeyPair: pair);

  setUpAll(() async => pair = await apkamKeyPairFromSeed(
      Uint8List.fromList(List.generate(32, (i) => i + 100))));

  setUp(() async {
    server = _DocumentServer();
    derived = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
  });

  group('Given an AtServerAtKeysIo holding keys for @alice', () {
    late AtServerAtKeysIo io;

    setUp(() async {
      io = open();
      await io.write(
          _atSign,
          AtKeys.legacy(
              apkamPublicKey: _b('apkam-pub'),
              encryptionPublicKey: _b('enc-pub'),
              encryptionPrivateKey: _b('enc-priv'),
              selfEncryptionKey: _b('self-1'))
            ..atsign = alice);
    });

    CryptographicMaterial key({String value = 'YWRkZWQ='}) =>
        CryptographicMaterial(
          keyId: 'added',
          role: CryptographicMaterialRole.symmetricEncryption,
          algorithm: CryptographicMaterialAlgorithm.aes256,
          bytes: AtBytes.fromString(value),
          createdAt: DateTime.utc(2026, 1, 1),
        );

    bool holdsAdded(AtKeys keys) => keys.atSignKeysForKeyId('added').isNotEmpty;

    void addKey(AtKeys keys) {
      keys.addKey(key());
      expect(holdsAdded(keys), isTrue,
          reason: 'control: the change added the key to the keys it was '
              'handed');
    }

    /// What this store reads, and what a store opened afresh on the same
    /// document reads.
    Future<List<AtKeys>> reads() async =>
        [await io.read(_atSign), await open().read(_atSign)];

    test(
        'when an update adds a key and returns false, then a read does not '
        'hold the key', () async {
      await io.update(alice, (keys) {
        addKey(keys);
        return false;
      });

      for (final read in await reads()) {
        expect(holdsAdded(read), isFalse);
      }
    });

    test(
        'when an update adds a key and then throws, then the throw reaches the '
        'caller and a read does not hold the key', () async {
      await expectLater(
          io.update(alice, (keys) {
            addKey(keys);
            throw _Refused();
          }),
          throwsA(isA<_Refused>()));

      for (final read in await reads()) {
        expect(holdsAdded(read), isFalse);
      }
    });

    test(
        'when an update adds one key and a second add throws, then a read '
        'holds neither key', () async {
      await expectLater(
          io.update(alice, (keys) {
            addKey(keys);
            keys.addKey(key(value: 'b3RoZXI='));
            return true;
          }),
          throwsA(isA<ArgumentError>()),
          reason: 'the keys refuse a second key with the same id and role');

      for (final read in await reads()) {
        expect(holdsAdded(read), isFalse);
      }
    });

    test(
        'when an update adds a key and returns true, then a read holds the key',
        () async {
      await io.update(alice, (keys) {
        addKey(keys);
        return true;
      });

      for (final read in await reads()) {
        expect(holdsAdded(read), isTrue);
        expect(read.atsign, alice);
      }
    });
  });
}

class _Refused implements Exception {}
