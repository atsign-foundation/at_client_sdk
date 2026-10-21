import 'dart:convert' show base64Encode;

import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_commons/at_commons.dart' show AtKey;

import 'catalogue.dart';

/// Everything an app can observe of what the seed wrote, as plain JSON: each
/// record's value, the keys a scan of [namespace] lists, and each collection
/// item, by `owner:id`, with its readers.
///
/// A read that throws is recorded as the exception's type, so a record one
/// version reads and another cannot shows up as a difference rather than
/// stopping the snapshot. [pending] is left out: the seed writes it after
/// taking this, and it is checked on the atServer instead.
Future<Map<String, Object?>> snapshot(AtClient client,
    {required String me,
    required String peer,
    required String namespace}) async {
  final records = <String, Object?>{
    for (final record in catalogue)
      record.name: await _read(
          client, record.keyFor(me: me, peer: peer, namespace: namespace)),
  };

  final pendingKey =
      pending.keyFor(me: me, peer: peer, namespace: namespace).toString();
  final keys = (await client.getAtKeys(regex: namespace))
      .map((k) => k.toString())
      .where((k) => k != pendingKey)
      .toList()
    ..sort();

  final items = await client.collection<String>(
      collectionNamespace(namespace), itemLifetime);
  final itemFacts = <String, Object?>{
    for (final item in await items.getItems())
      '${item.owner}:${item.id}': {
        'obj': item.obj,
        'sharedWith': item.sharedWith.map((a) => '$a').toList()..sort(),
        'readBy': (await item.readBy).map((a) => '$a').toList()..sort(),
        'wasMarkedReadByMe': await item.wasMarkedReadByMe(),
      },
  };

  return {'records': records, 'keys': keys, 'items': itemFacts};
}

Future<Map<String, Object?>> _read(AtClient client, AtKey key) async {
  try {
    final atValue = await client.get(key);
    final value = atValue.value;
    return {
      'value': value is List<int> ? base64Encode(value) : value,
      'isBinary': atValue.metadata?.isBinary ?? false,
    };
  } catch (e) {
    return {'error': '${e.runtimeType}'};
  }
}
