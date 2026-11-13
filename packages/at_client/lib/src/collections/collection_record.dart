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

/// Thrown by [AtClient.collection] and [AtCollection.subCollection] when the
/// collection is already typed with a tag other than the one the open asked
/// for.
///
/// The open asks for its `writeTypeTag`, or its `typeTag` when it gives no
/// `writeTypeTag`. A collection is typed by its collection record, or by an
/// earlier open of the same namespace on the same [AtClient] that asked for a
/// tag. Nothing is written and no collection is handed out.
final class CollectionTypeTagMismatchException implements Exception {
  /// The collection's namespace.
  final String namespace;

  /// The tag the collection is already typed with: its record's, or the one
  /// an earlier open on this client asked for.
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

  /// The tag each namespace in [_byKey] is typed with on this client: its
  /// record's, else the first tag an open of it asked for. Keeps an open
  /// with a factory `typeTag`, which writes no record, from being reopened
  /// with another tag. Has no more keys than [_byKey].
  final Map<String, String> _tags = {};

  /// The collection for [namespace] and [eventSource], built by [build] with
  /// the tag it must stamp if this registry holds none yet.
  ///
  /// The open asks for [writeTypeTag], or [typeTag] when [writeTypeTag] is
  /// null. An earlier open of [namespace] on this registry that asked for
  /// another tag throws [CollectionTypeTagMismatchException] before the
  /// record is read. Then the collection record of [atClient]'s atSign is
  /// read: a record whose tag differs from the one asked for throws the same;
  /// with no record, [writeTypeTag] is written as the record. Every
  /// collection this registry holds for [namespace] then stamps the record's
  /// tag. An open that asks for no tag adopts the record's tag, else the tag
  /// an earlier open asked for. Throws [ArgumentError] for tag arguments a
  /// collection refuses, before anything is read or written.
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
    final asked = writeTypeTag ?? typeTag;
    return _opening.protect(() async {
      final held = _tags[namespace];
      _refuseOtherTag(namespace, held: held, asked: asked);
      final tag = await _openRecord(
        atClient,
        namespace,
        asked: asked,
        claim: writeTypeTag,
      );
      final c = _byKey.putIfAbsent((namespace, eventSource),
          () => build(tag ?? (asked == null ? held : null))) as AtCollection<T>;
      final typedAs = tag ?? held ?? asked;
      if (typedAs != null) _tags[namespace] = typedAs;
      if (tag != null) {
        for (final e in _byKey.entries) {
          if (e.key.$1 == namespace) e.value._writeTypeTag = tag;
        }
      }
      return c;
    });
  }
}

/// Throws [CollectionTypeTagMismatchException] when [namespace] is already
/// typed [held] and the open [asked] for another tag.
void _refuseOtherTag(
  String namespace, {
  required String? held,
  required String? asked,
}) {
  if (held != null && asked != null && asked != held) {
    throw CollectionTypeTagMismatchException(namespace,
        recordedTag: held, requestedTag: asked);
  }
}

/// The most sub-collection namespaces whose tag one [AtClient] remembers;
/// past it the oldest is forgotten. A sub-collection namespace holds its
/// parent item's id, which can come from another atSign, so the map is
/// bounded.
const int _maxSubCollectionTags = 4096;

/// For each [AtClient], the tag each sub-collection namespace was first
/// opened with by [AtCollection.subCollection], oldest first. Sub-collections
/// keep no record on the atServer, so this is what stops a reopen on the same
/// client from silently taking another tag.
final Expando<Map<String, String>> _subCollectionTags = Expando();

/// The tag a sub-collection [namespace] of [atClient] must stamp, after
/// checking the open's tags against an earlier open of it.
///
/// Throws [CollectionTypeTagMismatchException] when an earlier open asked for
/// another tag than [writeTypeTag], or [typeTag] when [writeTypeTag] is null.
/// An open that asks for no tag adopts the earlier one. Call [_noteSubTag]
/// once the sub-collection is built.
String? _subCollectionStamp(
  AtClient atClient,
  String namespace, {
  required String? typeTag,
  required String? writeTypeTag,
}) {
  final asked = writeTypeTag ?? typeTag;
  final held = _subCollectionTags[atClient]?[namespace];
  _refuseOtherTag(namespace, held: held, asked: asked);
  return writeTypeTag ?? (asked == null ? held : null);
}

/// Remembers that sub-collection [namespace] of [atClient] was opened asking
/// for [asked]. [_subCollectionStamp] has already refused any other tag, so
/// this never changes a tag already held.
void _noteSubTag(AtClient atClient, String namespace, String? asked) {
  if (asked == null) return;
  final tags = _subCollectionTags[atClient] ??= <String, String>{};
  tags[namespace] = asked;
  if (tags.length > _maxSubCollectionTags) tags.remove(tags.keys.first);
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
