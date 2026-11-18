import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_client/src/passkey/at_keys_document.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_client/src/passkey/passkey_custody.dart'
    show MissingAtKeysDocumentException;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../support/custody_fakes.dart';
import '../support/lookup_fakes.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';

String _b(String s) => base64Encode(utf8.encode(s));

AtKeys _base() => AtKeys.legacy(
    apkamPublicKey: _b('apkam-pub'),
    encryptionPublicKey: _b('enc-pub'),
    encryptionPrivateKey: _b('enc-priv'),
    selfEncryptionKey: _b('self-1'))
  ..atsign = _atSign.toAtsign();

/// An atServer holding documents by key, with a log of every command. It
/// grants every create of a document's lock.
class _FakeAtServer {
  final records = <String, String>{};
  final commands = <String>[];

  /// Accepts updates without storing them.
  var dropUpdates = false;

  /// Fails the next update with an error reply, storing nothing.
  var failNextUpdate = false;

  /// Answers every lookup after the first update with a document that does not
  /// open.
  var corruptAfterUpdate = false;

  /// Yields to the event loop after each lookup read, so that two operations
  /// that are not serialised interleave between their read and their put.
  var yieldOnRead = false;

  /// When set, an update command waits for it after it is logged and signals
  /// [updateArrived], so a test can act while a write is in flight.
  Completer<void>? holdUpdate;
  final updateArrived = Completer<void>();

  /// When set, the next lookup waits for it after it is logged and signals
  /// [lookupArrived], so a test can act while a write reads.
  Completer<void>? holdLookup;
  final lookupArrived = Completer<void>();

  Future<String?> respond(String command) async {
    commands.add(command);
    final line = command.substring(0, command.length - 1);
    if (line.startsWith('llookup:')) {
      final hold = holdLookup;
      if (hold != null) {
        holdLookup = null;
        lookupArrived.complete();
        await hold.future;
      }
      if (corruptAfterUpdate && updates.isNotEmpty) {
        return 'data:not-a-sealed-doc';
      }
      final value = records[line.substring('llookup:'.length)];
      if (yieldOnRead) await Future<void>.delayed(Duration.zero);
      if (value == null) throw AtLookUpException('AT0015', 'key not found');
      return 'data:$value';
    }
    if (line.startsWith('update:') && line.contains('atkeys-lock.')) {
      return 'data:-1';
    }
    if (line.startsWith('update:')) {
      if (failNextUpdate) {
        failNextUpdate = false;
        throw AtLookUpException('AT0011', 'internal server error');
      }
      if (!updateArrived.isCompleted) updateArrived.complete();
      await holdUpdate?.future;
      final body = line.substring('update:'.length);
      final split = body.indexOf(' ');
      if (!dropUpdates) {
        records[body.substring(0, split)] = body.substring(split + 1);
      }
      return 'data:1';
    }
    throw StateError('unexpected command $command');
  }

  /// Every update of a document, leaving out lock creates.
  List<String> get updates => commands
      .where((c) => c.startsWith('update:') && !c.contains('atkeys-lock.'))
      .toList();
}

void main() {
  late _FakeAtServer server;
  late DerivedKeys derived;
  late ApkamKeyPair pair;
  final key = enrollmentDocumentKey(_eid, _atSign);

  RemoteEnrollmentDocumentStore documents() => RemoteEnrollmentDocumentStore(
      RemoteSecondary(_atSign, AtClientPreference(),
          atLookUp: ScriptedAtLookUp(server.respond),
          lookUps: RecordingLookUps((_) async => null).call));

  Future<AtServerAtKeysIo> open({DerivedKeys? keys}) async {
    final k = keys ?? derived;
    return AtServerAtKeysIo(
        documents: documents(),
        atSign: _atSign,
        seal: (d) => k.vault.seal(PasskeyRecordType.atkeys, d),
        open: (r) => k.vault.open(PasskeyRecordType.atkeys, r),
        enrollmentId: _eid,
        apkamKeyPair: pair);
  }

  Future<void> seedRecord(AtKeys keys) async => server.records[key] =
      await derived.vault.seal(PasskeyRecordType.atkeys, keys.toJson());

  Future<AtKeys> stored(DerivedKeys keys) async => AtKeys.fromJson(
      await keys.vault.open(PasskeyRecordType.atkeys, server.records[key]!));

  setUpAll(() async => pair = await apkamKeyPairFromSeed(
      Uint8List.fromList(List.generate(32, (i) => i + 100))));

  setUp(() async {
    server = _FakeAtServer();
    derived = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
  });

  /// The legacy fields of [keys] with no typed material, which is where the
  /// overlay and the stripped document differ.
  Map<String, dynamic> coreOf(AtKeys keys) => atKeysDocument(keys, _atSign)
    ..remove('enrollments')
    ..remove('version')
    ..remove('atsign')
    ..remove('keys');

  /// What a read returns: [written] with the APKAM private key replaced by
  /// the derived pair, filed as the enrollment's authentication material.
  Future<void> expectOverlaid(AtKeys read, AtKeys written) async {
    expect(read.holdsAuthenticationMaterial, isTrue);
    expect(read.enrollmentToAuthenticateAs(), _eid);
    expect(coreOf(read), coreOf(written));
  }

  group('construction', () {
    AtServerAtKeysIo build(
            {Duration lockTtl = const Duration(seconds: 10),
            Duration lockWait = const Duration(seconds: 15)}) =>
        AtServerAtKeysIo(
            documents: documents(),
            atSign: _atSign,
            seal: (d) => derived.vault.seal(PasskeyRecordType.atkeys, d),
            open: (r) => derived.vault.open(PasskeyRecordType.atkeys, r),
            enrollmentId: _eid,
            apkamKeyPair: pair,
            lockTtl: lockTtl,
            lockWait: lockWait);
    Matcher naming(String name) =>
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', name));

    test('refuses a lockTtl under a millisecond', () {
      expect(() => build(lockTtl: Duration.zero), naming('lockTtl'),
          reason: 'a lock record with ttl 0 never expires');
    });

    test('refuses a lockTtl over the server mutex cap', () {
      expect(
          () => build(
              lockTtl: maxServerMutexTtl + const Duration(milliseconds: 1)),
          naming('lockTtl'),
          reason: 'a lock longer than the cap is not one a server mutex takes');
    });

    test('refuses a lockWait that is not positive', () {
      expect(() => build(lockWait: Duration.zero), naming('lockWait'),
          reason: 'a write that may not wait cannot take the lock');
      expect(() => build(lockWait: const Duration(milliseconds: -1)),
          naming('lockWait'));
    });

    test('refuses a lockWait not longer than half the lockTtl', () {
      expect(
          () => build(
              lockTtl: const Duration(minutes: 1),
              lockWait: const Duration(seconds: 15)),
          naming('lockWait'),
          reason: 'a lease too short to reuse holds the lock against the '
              "store's own next take for up to half the ttl");
      expect(
          () => build(
              lockTtl: const Duration(seconds: 10),
              lockWait: const Duration(seconds: 5)),
          naming('lockWait'));
    });

    test('accepts a lockTtl of the cap with a lockWait just over half of it',
        () {
      expect(
          build(
              lockTtl: maxServerMutexTtl,
              lockWait:
                  maxServerMutexTtl ~/ 2 + const Duration(milliseconds: 1)),
          isA<AtServerAtKeysIo>());
      expect(
          build(
              lockTtl: const Duration(milliseconds: 1),
              lockWait: const Duration(milliseconds: 1)),
          isA<AtServerAtKeysIo>());
    });
  });

  test('write then reload then read round-trips at the enrollment key',
      () async {
    final keys = _base();
    await (await open()).write(_atSign, keys);
    expect(server.records.keys, [key]);
    final reload = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
    final reopened = await open(keys: reload);
    await expectOverlaid(await reopened.read(_atSign), keys);
  });

  test('onboarding writes and a later open reads', () async {
    final keys = _base();
    await (await open()).write(_atSign, keys);
    final later = await open();
    await expectOverlaid(await later.read(_atSign), keys);
  });

  test('the document on the server does not hold the plaintext keys', () async {
    await (await open()).write(_atSign, _base());
    expect(server.records[key], isNot(contains(_b('enc-priv'))));
  });

  test('write is create-only', () async {
    final io = await open();
    await io.write(_atSign, _base());
    final before = server.records[key];
    await expectLater(io.write(_atSign, _base()),
        throwsA(isA<AtKeysFileOverwriteException>()));
    expect(server.records[key], before);
  });

  test('write refuses keys of another atSign before any command', () async {
    final other = _base()..atsign = '@bob'.toAtsign();
    await expectLater(
        (await open()).write(_atSign, other),
        throwsA(isA<AtServerAtKeysWriteException>()
            .having((e) => e.message, 'message', isNot(contains('@bob')))));
    expect(server.commands, isEmpty);
  });

  test('flush refuses keys of another atSign before any command', () async {
    final io = await open();
    await io.write(_atSign, _base());
    server.commands.clear();
    final other = _base()..atsign = '@bob'.toAtsign();
    await expectLater(io.flush(_atSign.toAtsign(), other),
        throwsA(isA<AtServerAtKeysWriteException>()));
    expect(server.commands, isEmpty);
  });

  test('a refused atSign does not stop later writes of the right keys',
      () async {
    final io = await open();
    final other = _base()..atsign = '@bob'.toAtsign();
    await expectLater(
        io.write(_atSign, other), throwsA(isA<AtServerAtKeysWriteException>()));
    await io.write(_atSign, _base());
    expect(server.records.keys, [key]);
  });

  test('read of an absent document throws', () async {
    await expectLater(
        Future.sync(() async => (await open()).read(_atSign)),
        throwsA(isA<MissingAtKeysDocumentException>()
            .having((e) => e.enrollmentId, 'enrollmentId', _eid)));
    expect(server.updates, isEmpty);
    expect(server.commands, hasLength(1));
  });

  test('update reads, mutates and flushes the stored state', () async {
    await seedRecord(_base());
    await (await open()).update(_atSign.toAtsign(), (keys) {
      keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
      return true;
    });
    final now = await stored(derived);
    expect(now.enrollmentSymmetricKey, isNotNull);
  });

  test('two overlapping updates on one instance both land', () async {
    await seedRecord(_base());
    server.yieldOnRead = true;
    final io = await open();
    final first = io.update(_atSign.toAtsign(), (keys) {
      keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
      return true;
    });
    final second = io.update(_atSign.toAtsign(), (keys) {
      keys.fileSigningMaterial(
          enrollmentId: 'e9z9z9',
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: _b('sign-pub'),
          privateKey: _b('sign-priv'));
      return true;
    });
    await Future.wait([first, second]);
    final now = await stored(derived);
    expect(now.enrollmentSymmetricKey, isNotNull);
    expect(jsonEncode(now.toJson()), contains(_b('sign-priv')));
  });

  test('a queued update still runs when the one before it throws', () async {
    await seedRecord(_base());
    server.yieldOnRead = true;
    final io = await open();
    final first = io.update(_atSign.toAtsign(), (_) => throw StateError('x'));
    final second = io.update(_atSign.toAtsign(), (keys) {
      keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
      return true;
    });
    await expectLater(first, throwsA(isA<StateError>()));
    await second;
    expect((await stored(derived)).enrollmentSymmetricKey, isNotNull);
  });

  test('update that returns false writes nothing', () async {
    await seedRecord(_base());
    await (await open()).update(_atSign.toAtsign(), (_) => false);
    expect(server.updates, isEmpty);
  });

  test('flush validates and files the full state', () async {
    final keys = _base();
    await seedRecord(keys);
    final next = AtKeys.fromJson(keys.toJson())
      ..atsign = _atSign.toAtsign()
      ..fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
    await (await open()).flush(_atSign.toAtsign(), next);
    expect(await stored(derived), next);
  });

  test('a read-back mismatch throws and leaves the document unchanged',
      () async {
    await seedRecord(_base());
    final before = server.records[key];
    server.dropUpdates = true;
    await expectLater(
        (await open()).update(_atSign.toAtsign(), (keys) {
          keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
          return true;
        }),
        throwsA(isA<AtServerAtKeysWriteException>()));
    expect(server.records[key], before);
  });

  test('a read-back that does not open throws typed and refuses the next write',
      () async {
    server.corruptAfterUpdate = true;
    final io = await open();
    await expectLater(io.write(_atSign, _base()),
        throwsA(isA<AtServerAtKeysWriteException>()));
    final sent = server.commands.length;
    await expectLater(Future.sync(() => io.write(_atSign, _base())),
        throwsA(isA<AtServerAtKeysWriteException>()));
    await expectLater(Future.sync(() => io.flush(_atSign.toAtsign(), _base())),
        throwsA(isA<AtServerAtKeysWriteException>()));
    expect(server.commands, hasLength(sent),
        reason: 'nothing went on the wire');
  });

  test('after a read-back mismatch no further write is sent', () async {
    await seedRecord(_base());
    final io = await open();
    server.dropUpdates = true;
    await expectLater(
        io.update(_atSign.toAtsign(), (keys) {
          keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
          return true;
        }),
        throwsA(isA<AtServerAtKeysWriteException>()));
    server.dropUpdates = false;
    final sent = server.commands.length;
    await expectLater(Future.sync(() => io.flush(_atSign.toAtsign(), _base())),
        throwsA(isA<AtServerAtKeysWriteException>()));
    await expectLater(Future.sync(() => io.write(_atSign, _base())),
        throwsA(isA<AtServerAtKeysWriteException>()));
    expect(server.commands, hasLength(sent));
  });

  test('a failed write is not retried', () async {
    await seedRecord(_base());
    server.dropUpdates = true;
    await expectLater(
        (await open()).update(_atSign.toAtsign(), (keys) {
          keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
          return true;
        }),
        throwsA(isA<AtServerAtKeysWriteException>()));
    expect(server.updates, hasLength(1));
  });

  test(
      'two stores on one record: a change made while the other held a stale '
      'read is refused, typed, and the first change stays', () async {
    await seedRecord(_base());
    final w1Keys = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
    final w2Keys = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
    final w1 = await open(keys: w1Keys);
    final w2 = await open(keys: w2Keys);
    final w1Landed = Completer<void>();
    final w2Update = w2.update(_atSign.toAtsign(), (keys) async {
      await w1Landed.future;
      keys.fileLegacyMaterial(enrollmentId: 'w2');
      return true;
    });
    await Future<void>.delayed(Duration.zero);
    await w1.update(_atSign.toAtsign(), (keys) {
      keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
      return true;
    });
    final afterW1 = server.records[key];
    w1Landed.complete();

    await expectLater(w2Update, throwsA(isA<AtKeysAssuranceException>()));
    expect(server.records[key], afterW1, reason: 'a refusal changes nothing');
    expect((await stored(w1Keys)).enrollmentSymmetricKey, isNotNull);
    await expectLater(Future.sync(() => w2.flush(_atSign.toAtsign(), _base())),
        throwsA(isA<AtServerAtKeysWriteException>()));
  });

  test(
      'two stores that restored the same login snapshot: both updates land, '
      'neither is latched, and a later read is fresh', () async {
    await seedRecord(_base());
    Future<AtServerAtKeysIo> login() async {
      final vault = (await DerivedKeys.derive(
              Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign))
          .vault;
      return AtServerAtKeysIo(
          documents: documents(),
          atSign: _atSign,
          seal: (d) => vault.seal(PasskeyRecordType.atkeys, d),
          open: (r) => vault.open(PasskeyRecordType.atkeys, r),
          enrollmentId: _eid,
          apkamKeyPair: pair,
          restored: _base());
    }

    final a = await login();
    final b = await login();
    await a.update(_atSign.toAtsign(), (keys) {
      keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-a'));
      return true;
    });
    await b.update(_atSign.toAtsign(), (keys) {
      keys.fileLegacyMaterial(enrollmentId: 'enroll-b');
      return true;
    });
    final now = await stored(derived);
    expect(now.enrollmentSymmetricKey?.key, _b('sym-a'));
    expect(now.storedEnrollmentId, 'enroll-b');
    final read = await b.read(_atSign);
    expect(read.enrollmentSymmetricKey?.key, _b('sym-a'));
    expect(read.storedEnrollmentId, 'enroll-b');
    await b.update(_atSign.toAtsign(), (keys) => false);
  });

  test('a candidate that drops stored material is refused, record unchanged',
      () async {
    await seedRecord(_base());
    final before = server.records[key];
    final dropped = AtKeys.legacy(
        apkamPublicKey: _b('apkam-pub'), encryptionPublicKey: _b('enc-pub'))
      ..atsign = _atSign.toAtsign();
    await expectLater((await open()).flush(_atSign.toAtsign(), dropped),
        throwsA(isA<AtKeysAssuranceException>()));
    expect(server.records[key], before);
  });

  test('after a refusal further writes throw', () async {
    await seedRecord(_base());
    final io = await open();
    final dropped = AtKeys.legacy(
        apkamPublicKey: _b('apkam-pub'), encryptionPublicKey: _b('enc-pub'))
      ..atsign = _atSign.toAtsign();
    await expectLater(io.flush(_atSign.toAtsign(), dropped),
        throwsA(isA<AtKeysAssuranceException>()));
    final updatesBefore = server.updates.length;
    await expectLater(
        Future.sync(() => io.update(_atSign.toAtsign(), (keys) {
              keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
              return true;
            })),
        throwsA(isA<AtServerAtKeysWriteException>()));
    await expectLater(Future.sync(() => io.flush(_atSign.toAtsign(), _base())),
        throwsA(isA<AtServerAtKeysWriteException>()));
    expect(server.updates.length, updatesBefore);
  });

  test('every write re-fetches the stored document first', () async {
    await seedRecord(_base());
    final io = await open();
    for (final (i, material) in ['sym-x', 'sym-y'].indexed) {
      server.commands.clear();
      await io.update(_atSign.toAtsign(), (keys) {
        if (i == 0) keys.fileLegacyMaterial(apkamSymmetricKey: _b(material));
        return i == 0;
      });
      if (i == 0) {
        final documentCommands =
            server.commands.where((c) => !c.contains('atkeys-lock.')).toList();
        final firstUpdate =
            documentCommands.indexWhere((c) => c.startsWith('update:'));
        expect(firstUpdate, greaterThan(0));
        expect(documentCommands.first, startsWith('llookup:'));
      }
    }
  });

  group('another atSign', () {
    test('a read naming another atSign is refused and the store stays usable',
        () async {
      await seedRecord(_base());
      final io = await open();
      await io.read(_atSign);
      server.commands.clear();

      await expectLater(
          Future.sync(() => io.read('@bob')), throwsA(isA<ArgumentError>()));

      expect(server.commands, isEmpty);
      expect((await io.read(_atSign)).enrollmentToAuthenticateAs(), _eid);
    });

    test(
        'a write, flush, update or check naming another atSign is refused '
        'before any command', () async {
      await seedRecord(_base());
      final io = await open();
      final bob = '@bob'.toAtsign();
      final bobs = _base()..atsign = bob;

      await expectLater(io.write('@bob', bobs), throwsA(isA<ArgumentError>()));
      await expectLater(io.flush(bob, bobs), throwsA(isA<ArgumentError>()));
      await expectLater(
          io.update(bob, (keys) => true), throwsA(isA<ArgumentError>()));
      await expectLater(
          io.keepsAllOf('@bob', bobs), throwsA(isA<ArgumentError>()));

      expect(server.commands, isEmpty);
      await io.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
        return true;
      });
      expect((await stored(derived)).enrollmentSymmetricKey, isNotNull);
    });

    test('the atSign is compared in canonical form', () async {
      await seedRecord(_base());

      expect((await (await open()).read('@ALICE')).atsign, _atSign.toAtsign());
    });
  });

  group('an absent document', () {
    test('flush creates it', () async {
      final io = await open();

      await io.flush(_atSign.toAtsign(), _base());

      expect(coreOf(await stored(derived)), coreOf(_base()));
      await expectOverlaid(await io.read(_atSign), _base());
    });

    test('update throws and writes nothing', () async {
      await expectLater(
          (await open()).update(_atSign.toAtsign(), (keys) => true),
          throwsA(isA<MissingAtKeysDocumentException>()));
      expect(server.updates, isEmpty);
    });
  });

  group('failures that leave the store usable', () {
    test('a write over an existing document', () async {
      final io = await open();
      await io.write(_atSign, _base());
      await expectLater(io.write(_atSign, _base()),
          throwsA(isA<AtKeysFileOverwriteException>()));

      await io.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
        return true;
      });

      expect((await stored(derived)).enrollmentSymmetricKey, isNotNull);
    });

    test('a put that throws', () async {
      await seedRecord(_base());
      final io = await open();
      server.failNextUpdate = true;
      await expectLater(
          io.update(_atSign.toAtsign(), (keys) {
            keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
            return true;
          }),
          throwsA(isA<AtException>()));

      await io.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-y'));
        return true;
      });

      expect((await stored(derived)).enrollmentSymmetricKey?.key, _b('sym-y'));
    });
  });

  group('material of another enrollment', () {
    const other = 'f0other';
    final keyId =
        '${AtKeys.keyIdPrefix('auth', CryptographicMaterialAlgorithm.mlDsa65)}1';

    /// Every material [eid] holds in the stored document, as `role:bytes`.
    Future<List<String>> storedMaterialOf(String eid) async => [
          for (final e
              in ((await stored(derived)).toJson()['enrollments'] as List)
                  .cast<Map<String, dynamic>>())
            if (e['enrollmentId'] == eid)
              for (final k in e['keys'] as List)
                for (final m in (k as Map)['material'] as List)
                  '${(m as Map)['role']}:${m['bytes']}'
        ];

    test(
        'its public authentication key is kept, and this enrollment\'s own '
        'is not', () async {
      final keys = withApkamKey(_base(), _eid, pair)
        ..addKey(CryptographicMaterial(
            keyId: keyId,
            enrollmentId: other,
            role: CryptographicMaterialRole.publicAuthentication,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            bytes: AtBytes.fromString(_b('other-auth-pub')),
            createdAt: DateTime.now().toUtc()));

      await (await open()).write(_atSign, keys);

      expect(await storedMaterialOf(other),
          ['publicAuthentication:${_b('other-auth-pub')}'],
          reason: 'only the pair this store derives is left out');
      expect(await storedMaterialOf(_eid), isEmpty);
    });

    test(
        'its private authentication key, no longer active, is stripped and '
        'not refused', () async {
      final keys = _base()
        ..fileApkamMaterial(
            enrollmentId: other,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: _b('other-auth-pub'),
            privateKey: _b('other-auth-priv'))
        ..retireKey(other, keyId);
      withApkamKey(keys, _eid, pair);

      await (await open()).write(_atSign, keys);

      expect(await storedMaterialOf(other),
          ['publicAuthentication:${_b('other-auth-pub')}'],
          reason: 'only active private authentication material other than '
              'the pair is refused');
    });
  });

  group('enrollment entries', () {
    AtKeys withOwnSnapshot() => _base()
      ..recordEnrollmentSnapshot(_eid,
          namespaces: {'wavi': 'rw'}, appName: 'wavi', deviceName: 'browser');

    test(
        'an entry left with no keys keeps its namespaces, app and device names '
        'across a restart', () async {
      final keys = withOwnSnapshot();
      withApkamKey(keys, _eid, pair);
      await (await open()).write(_atSign, keys);

      final restarted = await (await open()).read(_atSign);

      final entry = (restarted.toJson()['enrollments'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((e) => e['enrollmentId'] == _eid);
      expect(entry['namespaces'], {'wavi': 'rw'});
      expect(entry['appName'], 'wavi');
      expect(entry['deviceName'], 'browser');
    });

    test('a document whose first entry has no keys left reads back as written',
        () async {
      final keys = withOwnSnapshot();
      withApkamKey(keys, _eid, pair);
      keys.fileSigningMaterial(
          enrollmentId: 'f0other',
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: _b('other-sign-pub'),
          privateKey: _b('other-sign-priv'));
      final io = await open();

      await io.write(_atSign, keys);
      await io.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
        return true;
      });

      expect((await stored(derived)).enrollmentSymmetricKey?.key, _b('sym-x'));
    });
  });

  group('close', () {
    test('after close a write, flush, update or read throws without I/O',
        () async {
      await seedRecord(_base());
      final io = await open();

      io.close();

      final typed = throwsA(isA<AtServerAtKeysWriteException>());
      await expectLater(io.flush(_atSign.toAtsign(), _base()), typed);
      await expectLater(io.update(_atSign.toAtsign(), (keys) => true), typed);
      await expectLater(io.write(_atSign, _base()), typed);
      await expectLater(Future.sync(() => io.read(_atSign)), throwsStateError);
      expect(server.commands, isEmpty, reason: 'no I/O after close');
    });

    test('zeroes the private key, so a read after close throws', () async {
      await seedRecord(_base());
      final io = await open();
      expect((await io.read(_atSign)).enrollmentToAuthenticateAs(), _eid);
      expect(io.holdsPrivateKey, isTrue);

      io.close();

      expect(io.holdsPrivateKey, isFalse);
      expect(Future.sync(() => io.read(_atSign)), throwsStateError);
    });

    test('leaves the vault it seals with open', () async {
      final io = await open();

      io.close();

      await derived.vault.withAuthSeed((_) async {});
      await derived.vault.seal(PasskeyRecordType.atkeys, {'a': 1});
    });

    test(
        'an update in flight finishes whole after close; one queued behind it '
        'is refused with no I/O', () async {
      await seedRecord(_base());
      final io = await open();
      final hold = Completer<void>();
      final running = io.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-x'));
        // Holds the re-read before the candidate is checked against the
        // stored document, a step that still reads the pair's private key.
        server.holdLookup = hold;
        return true;
      });
      await server.lookupArrived.future;
      final queued = io.update(_atSign.toAtsign(), (keys) => true);
      final queuedOutcome =
          expectLater(queued, throwsA(isA<AtServerAtKeysWriteException>()));

      io.close();
      expect(io.holdsPrivateKey, isTrue);
      hold.complete();

      await running;
      await queuedOutcome;
      expect(server.updates, hasLength(1));
      expect(io.holdsPrivateKey, isFalse);
      expect((await stored(derived)).enrollmentSymmetricKey?.key, _b('sym-x'));
      await expectLater(Future.sync(() => io.read(_atSign)), throwsStateError);
    });

    test('is idempotent', () async {
      final io = await open();

      io.close();
      io.close();

      await expectLater(Future.sync(() => io.read(_atSign)), throwsStateError);
    });
  });

  group('settled', () {
    test('completes once every write queued so far has ended', () async {
      await seedRecord(_base());
      final io = await open();
      server.holdUpdate = Completer<void>();
      final running = io.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-y'));
        return true;
      });
      await server.updateArrived.future;
      var settled = false;
      unawaited(io.settled.then((_) => settled = true));
      await pumpEventQueue();
      expect(settled, isFalse);

      server.holdUpdate!.complete();
      await running;
      await pumpEventQueue();

      expect(settled, isTrue);
    });

    test('completes when the write queued last failed', () async {
      final io = await open();
      final failing = expectLater(io.update(_atSign.toAtsign(), (keys) => true),
          throwsA(isA<MissingAtKeysDocumentException>()));

      await io.settled;
      await failing;
    });
  });

  group('keepsAllOf', () {
    test('is true for the stored keys themselves', () async {
      await seedRecord(_base());

      expect(await (await open()).keepsAllOf(_atSign, _base()), isTrue);
    });

    test('is true when the stored keys hold more than the candidate', () async {
      await seedRecord(_base());
      final fewer = AtKeys.legacy(
          apkamPublicKey: _b('apkam-pub'), encryptionPublicKey: _b('enc-pub'))
        ..atsign = _atSign.toAtsign();

      expect(await (await open()).keepsAllOf(_atSign, fewer), isTrue);
    });

    test('is false when the candidate holds what the stored keys lack',
        () async {
      final fewer = AtKeys.legacy(
          apkamPublicKey: _b('apkam-pub'), encryptionPublicKey: _b('enc-pub'))
        ..atsign = _atSign.toAtsign();
      await seedRecord(fewer);

      expect(await (await open()).keepsAllOf(_atSign, _base()), isFalse);
    });

    test('is false when the candidate holds different material', () async {
      await seedRecord(_base());
      final other = AtKeys.legacy(
          apkamPublicKey: _b('apkam-pub'),
          encryptionPublicKey: _b('enc-pub'),
          encryptionPrivateKey: _b('other-priv'),
          selfEncryptionKey: _b('self-1'))
        ..atsign = _atSign.toAtsign();

      expect(await (await open()).keepsAllOf(_atSign, other), isFalse);
    });

    test('changes nothing on the atServer', () async {
      await seedRecord(_base());
      final before = server.records[key];

      await (await open()).keepsAllOf(_atSign, _base());

      expect(server.updates, isEmpty);
      expect(server.records[key], before);
    });

    test('throws when there is no document', () async {
      await expectLater((await open()).keepsAllOf(_atSign, _base()),
          throwsA(isA<MissingAtKeysDocumentException>()));
    });
  });
}
