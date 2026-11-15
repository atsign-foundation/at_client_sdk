import 'dart:convert';

/// Notification pairs `(from, id)` kept in a watermark at one epochMillis.
const int watermarkIdCapacity = 1024;

/// Merges [mineJson] into [storedJson], the watermark already in the store,
/// and returns the JSON to store.
///
/// A stored value that is absent or not a watermark map yields [mineJson].
/// A higher stored `epochMillis` keeps the stored value unchanged, a lower one
/// yields [mineJson]. At an equal `epochMillis`, [mineJson]'s fields are kept
/// with `idsAtEpochMillis` set to the stored pairs followed by the pairs of
/// [mineJson] not already present, capped at [watermarkIdCapacity] newest.
String mergeWatermarkJson(String? storedJson, String mineJson) {
  final mine = jsonDecode(mineJson) as Map<String, dynamic>;
  final stored = _parseWatermark(storedJson);
  if (stored == null) return mineJson;

  final storedMillis = stored['epochMillis'] as int;
  final mineMillis = mine['epochMillis'] as int;
  if (storedMillis > mineMillis) return storedJson!;
  if (storedMillis < mineMillis) return mineJson;

  final seen = <String>{};
  final merged = <List<String>>[
    for (final pair in [..._pairs(stored), ..._pairs(mine)])
      if (seen.add(jsonEncode(pair))) pair,
  ];
  final kept = merged.length > watermarkIdCapacity
      ? merged.sublist(merged.length - watermarkIdCapacity)
      : merged;
  return jsonEncode({...mine, 'idsAtEpochMillis': kept});
}

Map<String, dynamic>? _parseWatermark(String? json) {
  if (json == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is Map<String, dynamic> && decoded['epochMillis'] is int) {
    return decoded;
  }
  return null;
}

List<List<String>> _pairs(Map<String, dynamic> watermark) {
  final raw = watermark['idsAtEpochMillis'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is List &&
          item.length >= 2 &&
          item[0] is String &&
          item[1] is String)
        [item[0] as String, item[1] as String],
  ];
}
