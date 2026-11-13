// The collection record: the type tag a collection was claimed with, kept on
// the atServer so every app, session and device of an atSign opens the
// collection with the same tag.

part of 'collections.dart';

/// The id of a collection's record, `__collection.<namespace>@<self>`. No
/// item may take it, and no key with it is read as an item: see
/// [_atKeyScanPrefix], which spells it out because a const raw string cannot
/// interpolate.
const String _recordId = '__collection';

/// The record version this client writes. A reader takes any version from 1
/// up and ignores the fields it does not know.
const int _recordVersion = 1;

/// The longest record value read, in UTF-16 code units, checked before it is
/// decoded. Room for the JSON Schema document a later version adds.
const int _maxRecordLength = 1024 * 1024;

final AtSignLogger _recordLogger = AtSignLogger(' AtCollection record ');

/// Thrown by [AtClient.collection] when the collection's record holds a type
/// tag other than the one the open asked for.
///
/// The open asks for its `writeTypeTag`, or its `typeTag` when it gives no
/// `writeTypeTag`. Nothing is written and no collection is handed out.
final class CollectionTypeTagMismatchException implements Exception {
  /// The collection's namespace.
  final String namespace;

  /// The tag the collection's record holds.
  final String recordedTag;

  /// The tag the open asked for.
  final String requestedTag;

  CollectionTypeTagMismatchException(
    this.namespace, {
    required this.recordedTag,
    required this.requestedTag,
  });

  @override
  String toString() => 'CollectionTypeTagMismatchException: the collection '
      '$namespace is typed "$recordedTag", not "$requestedTag"';
}

/// The collections one [AtClient] hands out, one per namespace and event
/// source, each opened against its collection record.
///
/// Opens run one at a time, so a check of the record and the write that
/// claims it are never split by another open on this client.
@internal
final class CollectionRegistry {
  final Map<(String, EventSource), AtCollection> _byKey = {};
  final Mutex _opening = Mutex();

  /// The collection for [namespace] and [eventSource], built by [build] with
  /// the tag it must stamp if this registry holds none yet.
  ///
  /// Reads the collection record of [atClient]'s atSign first. A record whose
  /// tag differs from [writeTypeTag], or from [typeTag] when [writeTypeTag] is
  /// null, throws [CollectionTypeTagMismatchException]; with no record,
  /// [writeTypeTag] is written as the record. Every collection this registry
  /// holds for [namespace] then stamps the record's tag. Throws
  /// [ArgumentError] for tag arguments a collection refuses, before anything
  /// is read or written.
  Future<AtCollection<T>> open<T>(
    AtClient atClient,
    String namespace,
    EventSource eventSource, {
    required bool hasFromJson,
    String? typeTag,
    String? writeTypeTag,
    required AtCollection<T> Function(String? writeTypeTag) build,
  }) {
    AtCollection._checkTagArgs<T>(
      hasFromJson: hasFromJson,
      typeTag: typeTag,
      writeTypeTag: writeTypeTag,
    );
    return _opening.protect(() async {
      final tag = await _openRecord(
        atClient,
        namespace,
        asked: writeTypeTag ?? typeTag,
        claim: writeTypeTag,
      );
      final c = _byKey.putIfAbsent((namespace, eventSource), () => build(tag))
          as AtCollection<T>;
      if (tag != null) {
        for (final e in _byKey.entries) {
          if (e.key.$1 == namespace) e.value._writeTypeTag = tag;
        }
      }
      return c;
    });
  }
}

/// The tag [namespace]'s record holds, after writing [claim] as the record
/// when there is none; null when there is none and nothing to claim.
///
/// Throws [CollectionTypeTagMismatchException] when the record holds a tag
/// other than [asked].
Future<String?> _openRecord(
  AtClient atClient,
  String namespace, {
  required String? asked,
  required String? claim,
}) async {
  final key = '$_recordId.$namespace${atClient.atSign}';
  var recorded = await _readRecord(atClient, key, remote: false);
  if (recorded == null && claim != null) {
    // NOTE: a record another client wrote may not have synced here yet, so
    // ask the atServer before claiming. Offline, claim locally: the record
    // then settles on sync, and a later open of the loser throws.
    try {
      recorded = await _readRecord(atClient, key, remote: true);
    } on FormatException {
      rethrow;
    } catch (e) {
      if (e is StoppedException) rethrow;
      _recordLogger.warning(
          'Could not read the collection record $key from the atServer, so '
          'it is claimed as "$claim" locally: $e');
    }
  }
  if (recorded != null) {
    if (asked != null && asked != recorded) {
      throw CollectionTypeTagMismatchException(namespace,
          recordedTag: recorded, requestedTag: asked);
    }
    return recorded;
  }
  if (claim == null) return null;
  await atClient.put(
    AtKey.fromString(key),
    jsonEncode({'v': _recordVersion, 'writeTypeTag': claim}),
  );
  return claim;
}

/// The tag the record at [key] holds, or null when there is no record; read
/// from the atServer when [remote] is true.
Future<String?> _readRecord(
  AtClient atClient,
  String key, {
  required bool remote,
}) async {
  final AtValue value;
  try {
    value = await atClient.get(
      AtKey.fromString(key),
      getRequestOptions:
          remote ? (GetRequestOptions()..useRemoteAtServer = true) : null,
    );
  } on AtKeyNotFoundException {
    return null;
  } on KeyNotFoundException {
    return null;
  }
  return _recordTag(value.value, key);
}

/// The type tag in [raw], the value of the record at [key].
///
/// Throws [FormatException] unless [raw] is a JSON object of at most
/// [_maxRecordLength] with an integer `v` of at least 1 and a non-blank
/// string `writeTypeTag`. Every other field is ignored.
String _recordTag(Object? raw, String key) {
  if (raw is! String) {
    throw FormatException('The collection record $key is not text');
  }
  if (raw.length > _maxRecordLength) {
    throw FormatException('The collection record $key is longer than '
        '$_maxRecordLength characters');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw FormatException('The collection record $key is not JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('The collection record $key is not a JSON object');
  }
  final v = decoded['v'];
  if (v is! int || v < 1) {
    throw FormatException('The collection record $key has no version');
  }
  final tag = decoded['writeTypeTag'];
  if (tag is! String || tag.trim().isEmpty) {
    throw FormatException('The collection record $key has no writeTypeTag');
  }
  return tag;
}
