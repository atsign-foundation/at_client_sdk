import 'dart:async';
import 'dart:io';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/io/memory_io.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

/// `update` — read, mutate and persist as one operation.
///
/// The defect it exists for: `flush` refuses a candidate that drops material,
/// which is the right contract, but a caller that reads *outside* the write's
/// critical section presents exactly that candidate whenever a sibling wrote in
/// between. The sibling is not hypothetical — an `AtClient`'s start fires the
/// namespace-key seeding and the conveyed-key filing as two unawaited tasks,
/// each doing its own read → mutate → flush on one keyfile.
///
/// Every test here runs the hand-rolled form as a control arm first. Without
/// that, "both keys survived" is equally explained by the two mutations never
/// having overlapped, and this file would pass while proving nothing.
void main() {
  late Directory tempDir;
  final atSign = '@alice🛠';

  String pathFor(String _) => '${tempDir.path}/keys.atKeys';

  CryptographicMaterial keyNamed(String keyId) => CryptographicMaterial(
        keyId: keyId,
        role: CryptographicMaterialRole.privateDecapsulation,
        algorithm: CryptographicMaterialAlgorithm.xWing,
        bytes: AtBytes.fromString('c2VlZA=='),
        createdAt: DateTime.utc(2026, 1, 1),
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('at_keys_update_test');
    await FileAtKeysIo(filePath: pathFor)
        .write(atSign, legacyAtKeys(atsign: atSign.toAtsign()));
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('FileAtKeysIo.update', () {
    test('the control arm: two concurrent read-mutate-flush pairs lose one',
        () async {
      final io = FileAtKeysIo(filePath: pathFor);

      Future<Object?> handRolled(String keyId) async {
        try {
          final keys = await io.read(atSign);
          // Both reads complete before either write starts — which is what two
          // sibling unawaited tasks do.
          await Future<void>.delayed(Duration.zero);
          keys.addKey(keyNamed(keyId));
          await io.flush(atSign.toAtsign(), keys);
          return null;
        } catch (e) {
          return e;
        }
      }

      final outcomes =
          await Future.wait([handRolled('first'), handRolled('second')]);

      expect(outcomes.whereType<AtKeysAssuranceException>(), hasLength(1),
          reason: 'the second flush presents a candidate without the first\'s '
              'addition, and assurance is right to refuse it — the loss is in '
              'the caller reading outside the write');
      final after = await io.read(atSign);
      expect(after.keys, hasLength(1),
          reason: 'one of the two additions is simply gone');
    });

    test('two concurrent updates both survive', () async {
      final io = FileAtKeysIo(filePath: pathFor);

      await Future.wait([
        io.update(atSign.toAtsign(), (keys) {
          keys.addKey(keyNamed('first'));
          return true;
        }),
        io.update(atSign.toAtsign(), (keys) {
          keys.addKey(keyNamed('second'));
          return true;
        }),
      ]);

      final after = await io.read(atSign);
      expect(
          after
              .getAtSignKey(
                  'first', CryptographicMaterialRole.privateDecapsulation)
              ?.bytes,
          isNotNull);
      expect(
          after
              .getAtSignKey(
                  'second', CryptographicMaterialRole.privateDecapsulation)
              ?.bytes,
          isNotNull,
          reason: 'the second update reads AFTER the first wrote, because the '
              'lock is held across its read as well as its write');
    });

    test('the mutation sees the state it is about to replace', () async {
      final io = FileAtKeysIo(filePath: pathFor);
      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('first'));
        return true;
      });

      var sawFirst = false;
      await io.update(atSign.toAtsign(), (keys) {
        sawFirst = keys.getAtSignKey(
                'first', CryptographicMaterialRole.privateDecapsulation) !=
            null;
        keys.addKey(keyNamed('second'));
        return true;
      });

      expect(sawFirst, isTrue);
    });

    test('returning false writes nothing', () async {
      final io = FileAtKeysIo(filePath: pathFor);
      final before = await File(pathFor(atSign)).readAsString();

      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('unwanted'));
        return false;
      });

      expect(await File(pathFor(atSign)).readAsString(), before,
          reason: 're-delivery is the substrate\'s normal mode, so a caller '
              'that finds the material already there must be able to say so '
              'without rewriting the store');
      expect((await io.read(atSign)).keys, isEmpty);
    });

    test('throwing from the mutation abandons the write', () async {
      final io = FileAtKeysIo(filePath: pathFor);
      final before = await File(pathFor(atSign)).readAsString();

      await expectLater(
        io.update(atSign.toAtsign(), (keys) {
          keys.addKey(keyNamed('unwanted'));
          throw StateError('changed my mind');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await File(pathFor(atSign)).readAsString(), before);
    });

    test('a retired enrollment cannot be discarded, and the update is refused',
        () async {
      final io = FileAtKeysIo(filePath: pathFor);
      CryptographicMaterial pendingHalf(String role) => CryptographicMaterial(
            keyId: 'auth:rsa2048:1',
            enrollmentId: 'e1',
            role: CryptographicMaterialRole.of(role),
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            bytes: AtBytes.fromString('cGVuZGluZw=='),
            createdAt: DateTime.utc(2026, 9, 12),
            status: CryptographicMaterialStatus.pending,
          );
      await io.update(atSign.toAtsign(), (keys) {
        keys
          ..addKey(pendingHalf('privateAuthentication'))
          ..addKey(pendingHalf('publicAuthentication'));
        return true;
      });
      await io.update(atSign.toAtsign(), (keys) {
        keys.activatePending('e1');
        return true;
      });
      await io.update(atSign.toAtsign(), (keys) {
        keys.retireKey('e1', 'auth:rsa2048:1');
        return true;
      });

      await expectLater(
        io.update(atSign.toAtsign(), (keys) {
          keys.discardEnrollment('e1');
          return true;
        }),
        throwsA(isA<ArgumentError>()),
        reason: 'discarding drops retired material, which the store refuses '
            'to lose. The refusal must happen HERE, before the instance loses '
            'it: the assurance exception a later flush raises leaves an '
            'AtKeys that can never be flushed again',
      );

      final after = await io.read(atSign);
      expect(after.keysForEnrollment('e1'), hasLength(2),
          reason: 'both halves are still on disk');
      expect(after.keysForEnrollment('e1').map((m) => m.status).toSet(),
          {CryptographicMaterialStatus.retired});
    });

    test('a mutation moving a status backward is still refused', () async {
      final io = FileAtKeysIo(filePath: pathFor);
      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('first'));
        return true;
      });
      await io.update(atSign.toAtsign(), (keys) {
        keys.retireAtSignKey('first');
        return true;
      });

      // `update` is a convenience over the write, not an escape from its
      // contract. It cannot present a candidate that has *lost* material —
      // `AtKeys` has no removal, which is the retire-never-remove rule — so
      // the reachable violation is a status going backward, and the same
      // assurance still catches it on the way out.
      final revived = AtKeys(atsign: atSign.toAtsign())
        ..addKey(keyNamed('first'));
      await expectLater(
        io.flush(atSign.toAtsign(), revived),
        throwsA(isA<AtKeysAssuranceException>()),
      );
    });

    test('update must not be called from inside another update', () async {
      // The lock is not reentrant, and the failure mode of nesting is a
      // ten-second wait on a lock this call already holds followed by a
      // FileSystemException — worth pinning, because the natural mistake is to
      // reach for `flush` inside a mutation.
      final io = FileAtKeysIo(
        filePath: pathFor,
      );
      await expectLater(
        io.update(atSign.toAtsign(), (keys) async {
          await io.flush(atSign.toAtsign(), keys);
          return false;
        }),
        throwsA(isA<FileSystemException>()),
      );
    }, timeout: Timeout(Duration(seconds: 40)));

    test('refuses a keyfile deleted while the update was in flight', () async {
      final io = FileAtKeysIo(filePath: pathFor);
      final file = File(pathFor(atSign));
      expect(file.existsSync(), isTrue,
          reason: 'control: setUp wrote the keyfile this update reads');

      // The owner deletes the keyfile between the read and the write. That is
      // not contrived: a client files key material from an unawaited startup
      // tail, and deleting `.atKeys` is how a device is decommissioned, so the
      // two land on the same isolate with awaits between them.
      await expectLater(
        io.update(atSign.toAtsign(), (keys) {
          file.deleteSync();
          expect(file.existsSync(), isFalse,
              reason: 'control: the delete took effect inside the mutate, so '
                  'the assertion below is about what update did next');
          keys.addKey(keyNamed('filed-during-the-delete'));
          return true;
        }),
        throwsA(isA<AtKeysSourceAbsentException>()),
      );

      expect(file.existsSync(), isFalse,
          reason: 'update must not resurrect a keyfile its owner deleted: the '
              'file IS the credential, so putting it back defeats the delete. '
              'It used to be recreated here, silently');
    });

    test('refuses a keyfile replaced while the update was in flight', () async {
      final io = FileAtKeysIo(filePath: pathFor);
      final file = File(pathFor(atSign));
      final restoredPath = '${tempDir.path}/restored.atKeys';
      await FileAtKeysIo(filePath: (_) => restoredPath).write(
          atSign,
          legacyAtKeys(atsign: atSign.toAtsign())
            ..apkamPrivateKey = AtBytes.fromString('cmVzdG9yZWQ='));
      final restored = File(restoredPath).readAsBytesSync();
      expect(restored, isNot(file.readAsBytesSync()),
          reason: 'control: the restored keyfile holds another credential');

      // The owner restores another keyfile over this one between the read
      // and the write, as the deletion above, by a path that does not take
      // the lock.
      await expectLater(
        io.update(atSign.toAtsign(), (keys) {
          file.writeAsBytesSync(restored);
          keys.addKey(keyNamed('filed-during-the-restore'));
          return true;
        }),
        throwsA(isA<AtKeysAssuranceException>()),
      );

      expect(file.readAsBytesSync(), restored,
          reason: 'the candidate is validated against the keyfile on disk at '
              'the write, and that keyfile is left as it was');
    });

    test('flush still creates the keyfile, which is what update must not do',
        () async {
      // The distinguishing arm. Both go through the same writer, and only
      // update refuses — so a change that made the writer refuse outright
      // would break this and not the test above.
      final io = FileAtKeysIo(filePath: pathFor);
      final file = File(pathFor(atSign));
      final keys = await io.read(atSign);
      file.deleteSync();
      expect(file.existsSync(), isFalse, reason: 'control: gone before flush');

      await io.flush(atSign.toAtsign(), keys);

      expect(file.existsSync(), isTrue,
          reason: 'flush means "persist these keys" and creating the file is '
              'its first job — a fresh keyfile has to come from somewhere');
    });
  });

  group('the default update', () {
    test('InMemoryAtKeysIo inherits read-mutate-flush', () async {
      final io = _CountingFlushesAtKeysIo();
      await io.write(atSign, legacyAtKeys(atsign: atSign.toAtsign()));

      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('first'));
        return true;
      });

      expect(io.flushes, 1,
          reason: 'a true return is "persist this", so flush must run — the '
              'control arm for the false-return test below');
      expect(
          (await io.read(atSign)).getAtSignKey(
              'first', CryptographicMaterialRole.privateDecapsulation),
          isNotNull);
    });

    test('and honours a false return', () async {
      final io = _CountingFlushesAtKeysIo();
      await io.write(atSign, legacyAtKeys(atsign: atSign.toAtsign()));

      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('first'));
        return false;
      });

      // Counting the flush, not re-reading the store: InMemoryAtKeysIo hands
      // `read` back the very instance the callback mutated, so the added key
      // is visible either way and a length check here passes just as well on
      // an update that ignored the false return entirely.
      expect(io.flushes, 0,
          reason: 're-delivery is the substrate\'s normal mode, so a caller '
              'that finds the material already there must be able to say so '
              'without writing the store');
    });
  });
}

/// An [InMemoryAtKeysIo] that counts the flushes it is asked to perform.
///
/// [InMemoryAtKeysIo] aliases the instance it stores, so an in-place mutation
/// made by an `update` callback is observable through `read` whether or not
/// the write happened. The flush count is the only thing that distinguishes
/// honouring the callback's false return from ignoring it.
class _CountingFlushesAtKeysIo extends InMemoryAtKeysIo {
  int flushes = 0;

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    flushes++;
    return super.flush(atsign, atKeys);
  }
}
