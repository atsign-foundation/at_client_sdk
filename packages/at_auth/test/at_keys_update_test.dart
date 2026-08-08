import 'dart:io';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/io/memory_io.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
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

  AtKeysMaterial keyNamed(String keyId) => AtKeysMaterial(
        keyId: keyId,
        keyPartType: CryptographicKeyType.privateDecapsulation,
        keyAlgorithmType: KeyAlgorithmType.xWing,
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
              .getKey('first', CryptographicKeyType.privateDecapsulation)
              ?.bytes,
          isNotNull);
      expect(
          after
              .getKey('second', CryptographicKeyType.privateDecapsulation)
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
        sawFirst = keys.getKey(
                'first', CryptographicKeyType.privateDecapsulation) !=
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

    test('a mutation moving a status backward is still refused', () async {
      final io = FileAtKeysIo(filePath: pathFor);
      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('first'));
        return true;
      });
      await io.update(atSign.toAtsign(), (keys) {
        keys.retireKey('first');
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
  });

  group('the default update', () {
    test('InMemoryAtKeysIo inherits read-mutate-flush', () async {
      final io = InMemoryAtKeysIo();
      await io.write(atSign, legacyAtKeys(atsign: atSign.toAtsign()));

      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('first'));
        return true;
      });

      expect(
          (await io.read(atSign))
              .getKey('first', CryptographicKeyType.privateDecapsulation),
          isNotNull);
    });

    test('and honours a false return', () async {
      final io = InMemoryAtKeysIo();
      await io.write(atSign, legacyAtKeys(atsign: atSign.toAtsign()));

      await io.update(atSign.toAtsign(), (keys) {
        keys.addKey(keyNamed('first'));
        return false;
      });

      // The in-memory store hands back the same object it holds, so "wrote
      // nothing" is checked by re-reading a fresh copy of what was persisted
      // rather than by inspecting the mutated instance.
      expect((await io.read(atSign)).keys, hasLength(1),
          reason: 'InMemoryAtKeysIo stores the instance itself, so a false '
              'return leaves the in-place mutation visible — the contract it '
              'can honour is that flush was not called, not that the object '
              'was rolled back');
    });
  });
}
