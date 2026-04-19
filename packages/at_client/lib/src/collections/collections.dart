import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart';

final class CItem<T> {
  static final Map<String, Function> _factories = {};

  static void registerFactory({
    required String type,
    required Function factory,
  }) {
    _factories[type] = factory;
  }

  /// The atSign which created this [CItem]. For example let's say we are
  /// currently `@alice`; then owner of a [CItem] which we create would be
  /// `@alice`. But the owner of a [CItem] shared with us by `@bob` will
  /// be `@bob`.
  ///
  /// [owner] is set by [AtCollection] when rehydrating stored data
  final Atsign owner;

  /// the unique identifier which will be prepended to the namespace of the
  /// collection for persistence. For example, if the collection has a
  /// namespace of `tasks.app_1.my_apps` then the full namespace of the
  /// persisted record will be `<id>.tasks.app_1.my_apps`
  ///
  /// [id] is set by [AtCollection] when rehydrating stored data
  final String id;

  /// The type name; this MUST be included in toJson() and fromJson()
  late final String type;

  /// the application's domain object
  final T obj;

  /// The [Atsign]s with which this data is shared
  final Set<Atsign> sharedWith;

  final Set<Atsign> readBy;

  DateTime createdAt;

  DateTime expiresAt;

  DateTime? availableAt;

  factory CItem.domain({
    required Atsign owner,
    required String type,
    required T obj,
    String? id,
    Set<Atsign>? sharedWith,
  }) {
    if (!_factories.containsKey(type)) {
      throw StateError('No factory registered for domain type $type');
    }
    final now = DateTime.now().toUtc();
    id ??= now.microsecondsSinceEpoch.toString();
    return CItem._(
      owner: owner,
      id: id,
      type: type,
      obj: obj,
      sharedWith: sharedWith ?? {},
      readBy: {},
      createdAt: now,
      expiresAt: now.add(Duration(days: 1)),
      availableAt: null,
    );
  }

  factory CItem.primitive({
    required Atsign owner,
    required T obj,
    String? id,
    Set<Atsign>? sharedWith,
  }) {
    final now = DateTime.now().toUtc();
    id ??= now.microsecondsSinceEpoch.toString();
    String type = (obj is Uint8List ? 'binary' : 'n/a');
    return CItem._(
      owner: owner,
      id: id,
      type: type,
      obj: obj,
      sharedWith: sharedWith ?? {},
      readBy: {},
      createdAt: now,
      expiresAt: now.add(Duration(days: 1)),
      availableAt: null,
    );
  }

  CItem._({
    required this.owner,
    required this.id,
    required this.type,
    required this.obj,
    required this.sharedWith,
    required this.readBy,
    required this.createdAt,
    required this.expiresAt,
    required this.availableAt,
  }) {
    if (obj is Uint8List && type != 'binary') {
      throw ArgumentError('factoryType for Uint8List must be "binary"');
    }
  }

  Map<String, dynamic> toJson() {
    if (type == 'binary') {
      return {
        'type': type,
        'readBy': readBy.toList(),
        'obj': Base2e15.encode(obj as Uint8List)
      };
    } else {
      return {'type': type, 'readBy': readBy.toList(), 'obj': obj};
    }
  }

  static T rehydrate<T>(Object obj, String type) {
    if (type == 'binary') {
      return Base2e15.decode(obj.toString()) as T;
    } else {
      final f = _factories[type];
      if (f == null) {
        return obj as T;
      } else {
        return f.call(obj) as T;
      }
    }
  }

  @override
  String toString() {
    return 'CItem{owner: $owner, sharedWith: $sharedWith, readBy: $readBy,'
        ' id: $id, type: $type, obj: ${obj.runtimeType},'
        ' expiresAt: $expiresAt, availableAt: $availableAt}';
  }
}

enum CollectionOp { put, delete }

sealed class OpResult {
  /// the [AtKey] for the operation
  final AtKey atKey;
  final CollectionOp op;

  OpResult(this.atKey, this.op);
}

class OpSuccess extends OpResult {
  OpSuccess(super.atKey, super.op);

  @override
  String toString() {
    return '$atKey:${op.name}:Success';
  }
}

class OpFailure extends OpResult {
  final Object reason;

  OpFailure(super.atKey, super.op, this.reason);

  @override
  String toString() {
    return '$atKey:${op.name}:Failure:$reason';
  }
}

typedef CollectionGetResponse<T> = ({List<CItem<T>> items, List exceptions});

sealed class CEvent {
  final Atsign owner;
  final String id;

  CEvent({
    required this.owner,
    required this.id,
  });
}

class CReadReceipt extends CEvent {
  final Atsign from;
  final DateTime readAt;

  CReadReceipt({
    required super.owner,
    required super.id,
    required this.from,
    required this.readAt,
  });
}

class CItemUpdated extends CEvent {
  CItemUpdated({
    required super.owner,
    required super.id,
  });
}

class CItemDeleted extends CEvent {
  CItemDeleted({
    required super.owner,
    required super.id,
  });
}

class CSubItemUpdated extends CEvent {
  final String subNamespace;

  CSubItemUpdated({
    required super.owner,
    required super.id,
    required this.subNamespace,
  });
}

class CSubItemDeleted extends CEvent {
  final String subNamespace;

  CSubItemDeleted({
    required super.owner,
    required super.id,
    required this.subNamespace,
  });
}

typedef CParts = ({
  Atsign from,
  String id,
  String? subNamespace,
  String? subId
});

class AtCollection<T> {
  static const String readReceiptNamespacePart = '__rr';
  static const String _rr = readReceiptNamespacePart;
  late final AtSignLogger logger;

  /// The [AtClient] we will use
  final AtClient atClient;

  Atsign get atSign => atClient.atSign;

  /// The fully qualified namespace. By fully qualified we mean
  /// that the namespace includes the "application namespace".
  ///
  /// i.e. if your application has a namespace of "app_1.my_apps"
  /// and your collection has a namespace of "tasks"
  /// then the full qualified namespace would be "tasks.app_1.my_apps"
  final String namespace;

  final Duration defaultExpiration;

  final StreamController<CEvent> _events = StreamController.broadcast();

  Stream<CEvent> get events => _events.stream;

  late final StreamSubscription<AtNotification> _rrSub;

  late final RegExp regexRR;
  late final RegExp regexObj;
  late final RegExp regexSubObj;
  late final String regexAllStr;

  AtCollection(
    this.atClient,
    this.namespace,
    this.defaultExpiration,
  ) {
    if (!namespace.contains('.')) {
      throw ArgumentError('namespaces must be fully qualified');
    }

    logger = AtSignLogger(' AtCollection<$T> $namespace ');

    regexRR = RegExp(':[^.]+\\.$_rr\\.[^.]+\\.$namespace@');
    regexAllStr = '.*\\.$namespace@';
    regexObj = RegExp('(^|:)[^.]+\\.$namespace@');
    regexSubObj = RegExp('(^|:)[^.]+\\.[^.]+\\.[^.]+\\.$namespace@');

    _rrSub = atClient.notificationService
        .subscribe(
          regex: regexAllStr,
          shouldDecrypt: true,
        )
        .listen(handleNotification);
  }

  @visibleForTesting
  Future<void> handleNotification(AtNotification n) async {
    _rrSub.pause();
    try {
      if (regexRR.hasMatch(n.key)) {
        await handleReadReceipt(n);
      } else if (regexObj.hasMatch(n.key)) {
        await handleObjNotification(n);
      } else {
        logger.shout('handleNotification: No handler for ${n.key}');
        // TODO add "subObj" notification handler
      }
    } catch (e, st) {
      logger.shout('handleNotification: $e\nStackTrace:\n$st');
    } finally {
      _rrSub.resume();
    }
  }

  CParts getPartsFromNotifKey(AtNotification n) {
    String keyName = n.key.replaceAll('${n.to}:', '').replaceAll(n.from, '');
    final ix = keyName.lastIndexOf('.$namespace');
    if (ix >= 0) {
      keyName = keyName.substring(0, ix);
    }
    final parts = keyName.split('.').reversed.toList();
    String id = parts[0];
    String? subSpace = parts.length > 1 ? parts[1] : null;
    String? subId = parts.length > 2 ? parts[2] : null;
    return (
      from: n.from.toAtsign(),
      id: id,
      subNamespace: subSpace,
      subId: subId,
    );
  }

  @visibleForTesting
  Future<void> handleReadReceipt(AtNotification n) async {
    // @to:rr_id.__rr.obj_id.some.name.space@from
    // -> obj_id.__rr.rr_id
    final parts = getPartsFromNotifKey(n);
    await markRead(
        (await get(id: parts.id, owner: atSign)).items.first, parts.from);
    _events.add(
      CReadReceipt(
        owner: atSign,
        id: parts.id,
        from: parts.from,
        readAt: DateTime.fromMicrosecondsSinceEpoch(int.parse(parts.subId!)),
      ),
    );
  }

  @visibleForTesting
  Future<void> handleObjNotification(AtNotification n) async {
    final parts = getPartsFromNotifKey(n);

    switch (n.operation) {
      case 'update':
        _events.add(CItemUpdated(owner: parts.from, id: parts.id));
        break;
      case 'delete':
        _events.add(CItemDeleted(owner: parts.from, id: parts.id));
        break;
      default:
        logger.shout('handleObjNotification:'
            ' No handler for operation ${n.operation}');
    }
  }

  Future<bool> sentReadReceipt(CItem<T> item) async {
    if (item.owner == atSign) {
      return true;
    }
    String regex = '${item.owner}:.*\\.$_rr\\.${item.id}\\.$namespace$atSign';
    final matches = await atClient.getKeys(regex: regex);
    return matches.isNotEmpty;
  }

  String get newId => DateTime.now().microsecondsSinceEpoch.toString();

  /// It is safe to call this multiple times; it will only be sent one time
  Future<bool> sendReadReceipt(CItem<T> item) async {
    if (await sentReadReceipt(item)) {
      return false;
    }
    String id = newId;
    AtKey k =
        AtKey.fromString('${item.owner}:$id.$_rr.${item.id}.$namespace$atSign');
    Metadata md = Metadata();
    md.ttr = -1; // recipient can cache
    md.ccd = true;
    DateTime now = DateTime.now();
    md.expiresAt = item.createdAt.add(Duration(days: 7));
    md.ttl = md.expiresAt!.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    if (item.availableAt != null) {
      md.availableAt = item.availableAt;
      md.ttb =
          md.availableAt!.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    }
    md.namespaceAware = false;

    await atClient.put(k, id);

    return true;
  }

  /// Get the list of all AtKeys in this collection
  /// - for [owner] if supplied
  /// - for [id] if supplied
  Future<List<AtKey>> getKeys({String? id, Atsign? owner}) async {
    // scan for matching AtKeys
    id ??= '[^.]+';
    String ownerFragment = owner ?? '@';
    final regex = '(^|:)$id\\.$namespace$ownerFragment';

    return (await atClient.getAtKeys(regex: regex))
      ..sort((a, b) => a.fullKeyAndOwner.compareTo(b.fullKeyAndOwner));
  }

  /// Returns a [CollectionGetResponse] with a [CItem] for every unique
  /// `id.collection.namespace@owner`. So for example if `@alice` has shared
  /// the same thing with both `@bob` and `@chuck`, that would be just one
  /// [CItem] in the response, with [CItem.owner] == `@alice` and
  /// [CItem.sharedWith] == `{'@bob','@chuck'}`
  ///
  /// Note that [CItem.id] identifiers are treated as unique within collections
  /// for a given [CItem.owner] but are not required to be unique across owners.
  ///
  /// Consider example of a `tasks` Collection with a [CItem] whose id is
  /// `1` - there may be MANY items in the overall collection with id 1, for
  /// example if `@alice` creates a task with ID 1 and shares it with bob, and
  /// `@bob` creates a task with ID of 1 and shares it with alice, then alice
  /// will have
  /// - `@bob:1.tasks.app_1.my_apps@alice`
  /// - `@alice:1.tasks.app_1.my_apps@bob`
  Future<CollectionGetResponse<T>> get({String? id, Atsign? owner}) async {
    Map<String, CItem<T>> map = {};
    List exceptions = [];

    for (final AtKey k in await getKeys(id: id, owner: owner)) {
      try {
        CItem<T> m;
        if (map.containsKey(k.fullKeyAndOwner)) {
          m = map[k.fullKeyAndOwner]!;
        } else {
          final AtValue v = await atClient.get(k);
          logger.info('Retrieved raw value ${v.value}');
          final decoded = jsonDecode(v.value!);
          m = CItem._(
            owner: k.sharedBy!.toAtsign(),
            id: k.key.split('.').first,
            type: decoded['type'],
            obj: CItem.rehydrate<T>(decoded['obj'], decoded['type']),
            sharedWith: {},
            readBy: (decoded['readBy'] as List)
                .map((e) => e.toString().toAtsign())
                .toSet(),
            createdAt: v.metadata!.createdAt!,
            expiresAt: v.metadata!.expiresAt!,
            availableAt: v.metadata!.availableAt,
          );
          map[k.fullKeyAndOwner] = m;
        }
        if (k.sharedWith != null) {
          m.sharedWith.add(k.sharedWith!.toAtsign());
        }
      } catch (e) {
        exceptions.add(e);
      }
    }
    return (items: map.values.toList(), exceptions: exceptions);
  }

  Future<List<CItem<T>>> getList({String? id, Atsign? owner}) async {
    final r = await get(id: id, owner: owner);
    if (r.exceptions.isNotEmpty) {
      throw Exception(r.exceptions.toString());
    }
    return r.items;
  }

  Future<void> markRead(CItem<T> item, Atsign readBy) async {
    item.readBy.add(readBy);
    await put(item);
  }

  /// - saves a copy of [item] for us (aka a 'self' copy)
  /// - saves a copy for each of [CItem.sharedWith]
  /// - if [unshareWithOthers] is true, deletes any copies for atSigns who
  ///   are not in [CItem.sharedWith]
  /// Returns a stream of [OpResult] for each action taken
  Future<List<OpResult>> put(
    CItem<T> item, {
    bool unshareWithOthers = true,
    DateTime? expiresAt,
    DateTime? availableAt,
  }) async {
    List<OpResult> l = [];
    if (item.owner != atSign) {
      throw ArgumentError('You may not update items owned by other atSigns');
    }

    AtKey selfKey = AtKey.fromString('${item.id}.$namespace$atSign');
    try {
      AtValue v = await atClient.get(selfKey);
      expiresAt = v.metadata?.expiresAt;
      availableAt = v.metadata?.availableAt;
      if (v.value != null) {
        final decoded = jsonDecode(v.value);
        final existingReadBy = (decoded['readBy'] as List)
            .map((e) => e.toString().toAtsign())
            .toSet();
        item.readBy.addAll(existingReadBy);
      }
    } catch (_) {}

    expiresAt ??= DateTime.now().add(defaultExpiration);

    final now = DateTime.now();
    if (expiresAt.millisecondsSinceEpoch < now.millisecondsSinceEpoch) {
      throw ArgumentError('expiresAt must be in the future');
    }

    Metadata md = Metadata();
    md.ttr = -1; // recipient can cache
    md.ccd = true;
    md.expiresAt = expiresAt;
    md.ttl = expiresAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    if (availableAt != null) {
      md.availableAt = availableAt;
      md.ttb = availableAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    }
    md.namespaceAware = false;

    /// save a copy for us (aka a 'self' copy) and yield a result
    try {
      selfKey.metadata = md;
      await atClient.put(
        selfKey,
        jsonEncode(item.toJson()),
      );
      l.add(OpSuccess(selfKey, CollectionOp.put));
    } catch (e) {
      l.add(OpFailure(selfKey, CollectionOp.put, e));
    }

    /// if [unshareWithOthers] is true, deletes any copies for atSigns who
    /// are not in item.sharedWith
    if (unshareWithOthers) {
      for (final AtKey k in await getKeys(id: item.id, owner: atSign)) {
        if ((k.sharedWith ?? atSign) == atSign) {
          continue;
        }
        try {
          await atClient.delete(k);
          l.add(OpSuccess(k, CollectionOp.delete));
        } catch (e) {
          l.add(OpFailure(k, CollectionOp.delete, e));
        }
      }
    }

    /// for each item in [shareWith], save a copy for them and yield a result
    for (final otherAtSign in item.sharedWith) {
      AtKey k = AtKey.fromString('$otherAtSign:${item.id}.$namespace$atSign');
      try {
        k.metadata = md;
        await atClient.put(
          k,
          jsonEncode(item.toJson()),
        );
        l.add(OpSuccess(k, CollectionOp.put));
      } catch (e) {
        l.add(OpFailure(k, CollectionOp.put, e));
      }
    }

    return l;
  }

  /// Deletes the object.
  /// - If owner was us, also deletes any copies shared with others.
  /// - If owner was other, deletes our cached copy of what was shared with us.
  Future<List<OpResult>> delete(CItem<T> item) async {
    if (item.owner != atSign) {
      throw ArgumentError('You may not delete items owned by other atSigns');
    }

    final List<OpResult> l = [];
    // delete all
    for (final AtKey k in await getKeys(id: item.id, owner: atSign)) {
      try {
        await atClient.delete(k);
        l.add(OpSuccess(k, CollectionOp.delete));
      } catch (e) {
        l.add(OpFailure(k, CollectionOp.delete, e));
      }
    }
    return l;
  }

  String prettyString(CItem<dynamic> m) {
    if (m.type == 'binary') {
      return '${m.id}.$namespace${m.owner}'
          '\n\tsharedWith: ${m.sharedWith}'
          '\n\treadBy: ${m.readBy}'
          '\n\texpiresAt: ${m.expiresAt}'
          '\n\tavailableAt: ${m.availableAt}'
          '\n\ttype: ${m.type}'
          '\n\truntimeType: ${m.obj.runtimeType}'
          '\n\tlength: ${m.obj.length} bytes'
          '';
    } else {
      return '${m.id}.$namespace${m.owner}'
          '\n\tsharedWith: ${m.sharedWith}'
          '\n\treadBy: ${m.readBy}'
          '\n\texpiresAt: ${m.expiresAt}'
          '\n\tavailableAt: ${m.availableAt}'
          '\n\ttype: ${m.type}'
          '\n\truntimeType: ${m.obj.runtimeType}'
          '\n\tobj: ${m.obj}'
          '';
    }
  }
}
