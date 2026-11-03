import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

/// The atSign floor a keyfile records: written by [AtKeys.raiseAtSignFloor]
/// alone, kept through every read and write in both document shapes, and
/// never lowered or removed by an update.
void main() {
  const atSign = '@alice🛠';
  late Directory dir;
  late FileAtKeysIo io;

  String path(String _) => '${dir.path}/keys.atKeys';
  Map<String, dynamic> onDisk() =>
      jsonDecode(File(path('')).readAsStringSync()) as Map<String, dynamic>;

  /// A keyfile in the typed shape, holding one atSign-level key.
  AtKeys typed() => legacyAtKeys(atsign: atSign.toAtsign())
    ..addKey(CryptographicMaterial(
      keyId: 'k',
      role: CryptographicMaterialRole.privateDecapsulation,
      algorithm: CryptographicMaterialAlgorithm.xWing,
      bytes: AtBytes.fromString('c2VlZA=='),
      createdAt: DateTime.utc(2026, 1, 1),
    ));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('at_keys_atsign_floor_test');
    io = FileAtKeysIo(filePath: path);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('raising records pqReady once, and raising again changes nothing', () {
    final keys = typed();
    expect(keys.atSignFloor, isNull);

    expect(keys.raiseAtSignFloor(AtKeys.atSignFloorPqReady), isTrue);
    expect(keys.atSignFloor, 'pqReady');
    expect(keys.raiseAtSignFloor(AtKeys.atSignFloorPqReady), isFalse);
    expect(keys.atSignFloor, 'pqReady');
  });

  test('raising to a floor this build does not know is refused', () {
    expect(() => typed().raiseAtSignFloor('pqActive'), throwsArgumentError);
  });

  for (final (shape, build) in [
    ('typed', typed),
    ('flat', () => legacyAtKeys(atsign: atSign.toAtsign())),
  ]) {
    test('in the $shape shape it is written and read back', () async {
      await io.write(atSign, build());
      await io.update(atSign.toAtsign(),
          (keys) => keys.raiseAtSignFloor(AtKeys.atSignFloorPqReady));

      expect(onDisk()['atsignFloor'], 'pqReady');
      expect(onDisk().containsKey('version'), shape == 'typed',
          reason: 'the control: the document is in the $shape shape');
      final read = await io.read(atSign);
      expect(read.atSignFloor, 'pqReady');
      expect(read.metadata.containsKey('atsignFloor'), isFalse,
          reason: 'it is a field of its own, not an unknown one carried along');
    });

    test(
        'in the $shape shape an update that drops it is refused, and the '
        'keyfile keeps it', () async {
      await io.write(atSign, build());
      final stale = await io.read(atSign);
      await io.update(atSign.toAtsign(),
          (keys) => keys.raiseAtSignFloor(AtKeys.atSignFloorPqReady));

      await expectLater(
          io.flush(atSign.toAtsign(), stale),
          throwsA(isA<AtKeysAssuranceException>().having((e) => e.message,
              'message', contains('floor pqReady is never lowered'))),
          reason: 'refused by the floor\'s own rule, not as an unknown field '
              'the never-lose check happens to preserve');
      expect(onDisk()['atsignFloor'], 'pqReady');
    });
  }

  test('a floor this build does not know is read and kept', () async {
    await io.write(atSign, typed());
    final raw = onDisk()..['atsignFloor'] = 'pqActive';
    File(path('')).writeAsStringSync(jsonEncode(raw));

    await io.update(atSign.toAtsign(), (keys) {
      expect(keys.atSignFloor, 'pqActive');
      expect(keys.raiseAtSignFloor(AtKeys.atSignFloorPqReady), isFalse);
      return true;
    });

    expect(onDisk()['atsignFloor'], 'pqActive');
  });

  group('the update assurance', () {
    const assurance = AtKeysAssurance();

    test('refuses a candidate that changes the floor', () {
      expect(
          () => assurance.validateMapUpdate(
              existing: {'atsignFloor': 'pqReady'},
              candidate: {'atsignFloor': 'pqActive'}),
          throwsA(isA<AtKeysAssuranceException>().having((e) => e.message,
              'message', contains('floor pqReady is never lowered'))));
    });

    test('accepts one that keeps it, and one that records it', () {
      assurance.validateMapUpdate(
          existing: {'atsignFloor': 'pqReady'},
          candidate: {'atsignFloor': 'pqReady'});
      assurance.validateMapUpdate(
          existing: {}, candidate: {'atsignFloor': 'pqReady'});
    });
  });

  test('two keyfiles that differ only in their floor are not equal', () {
    final raised = typed()..raiseAtSignFloor(AtKeys.atSignFloorPqReady);
    expect(raised, isNot(typed()));
    expect(typed(), typed(), reason: 'the control');
  });
}
