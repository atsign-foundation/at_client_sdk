import 'dart:convert';

import 'package:at_client/src/service/watermark_merge.dart';
import 'package:test/test.dart';

String watermark({
  required int epochMillis,
  required List<List<String>> ids,
  String id = 'latest',
}) =>
    jsonEncode({
      'id': id,
      'from': '@alice',
      'to': '@alice',
      'key': '$id.wavi@alice',
      'operation': 'update',
      'epochMillis': epochMillis,
      'messageType': 'MessageType.key',
      'isEncrypted': false,
      'idsAtEpochMillis': ids,
    });

Map<String, dynamic> decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

List<List<String>> idsOf(String json) =>
    (decode(json)['idsAtEpochMillis'] as List)
        .map((p) => (p as List).cast<String>())
        .toList();

void main() {
  group('mergeWatermarkJson', () {
    test('a null stored value yields mine', () {
      final mine = watermark(epochMillis: 100, ids: [
        ['@alice', 'a']
      ]);

      expect(mergeWatermarkJson(null, mine), mine);
    });

    test('an unparsable stored value yields mine', () {
      final mine = watermark(epochMillis: 100, ids: [
        ['@alice', 'a']
      ]);

      expect(mergeWatermarkJson('{not json', mine), mine);
    });

    test('a stored value that is not a watermark map yields mine', () {
      final mine = watermark(epochMillis: 100, ids: [
        ['@alice', 'a']
      ]);

      expect(mergeWatermarkJson('[1,2,3]', mine), mine);
      expect(mergeWatermarkJson('{"epochMillis":"soon"}', mine), mine);
    });

    test('a stored watermark with a higher epochMillis is kept unchanged', () {
      final stored = watermark(epochMillis: 200, ids: [
        ['@bob', 'b']
      ]);
      final mine = watermark(epochMillis: 100, ids: [
        ['@alice', 'a']
      ]);

      expect(mergeWatermarkJson(stored, mine), stored);
    });

    test('a stored watermark with a lower epochMillis yields mine', () {
      final stored = watermark(epochMillis: 50, ids: [
        ['@bob', 'b']
      ]);
      final mine = watermark(epochMillis: 100, ids: [
        ['@alice', 'a']
      ]);

      expect(mergeWatermarkJson(stored, mine), mine);
    });

    test(
        'at an equal epochMillis, mine fields are kept and the stored ids come '
        'first, then mine not already present', () {
      final stored = watermark(epochMillis: 100, id: 'old', ids: [
        ['@bob', 'b1'],
        ['@alice', 'a1'],
      ]);
      final mine = watermark(epochMillis: 100, id: 'new', ids: [
        ['@alice', 'a1'],
        ['@alice', 'a2'],
      ]);

      final merged = mergeWatermarkJson(stored, mine);

      expect(
          idsOf(merged),
          [
            ['@bob', 'b1'],
            ['@alice', 'a1'],
            ['@alice', 'a2'],
          ],
          reason: 'duplicates are dropped and the stored order is kept');
      expect(decode(merged)['id'], 'new', reason: 'every other field is mine');
      expect(decode(merged)['epochMillis'], 100);
    });

    test('an equal epochMillis keeps only the newest watermarkIdCapacity ids',
        () {
      expect(watermarkIdCapacity, 1024);
      final stored = watermark(epochMillis: 100, ids: [
        for (var i = 0; i < watermarkIdCapacity; i++) ['@alice', 's$i'],
      ]);
      final mine = watermark(epochMillis: 100, ids: [
        ['@alice', 'm'],
      ]);

      final merged = idsOf(mergeWatermarkJson(stored, mine));

      expect(merged.length, watermarkIdCapacity);
      expect(merged.first, ['@alice', 's1'],
          reason: 'the oldest id is dropped from the head');
      expect(merged.last, ['@alice', 'm'],
          reason: 'mine is the newest and is kept');
    });
  });
}
