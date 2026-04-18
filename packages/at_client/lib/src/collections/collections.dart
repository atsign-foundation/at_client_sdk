import 'dart:typed_data';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_base2e15/at_base2e15.dart';

final class Model<T> {
  static final Map<String, Function> _factories = {};

  static void registerFactory({
    required String type,
    required Function factory,
  }) {
    _factories[type] = factory;
  }

  /// The atSign which created this Model. For example let's say we are
  /// currently `@alice`; then owners of Models which we create would be
  /// `@alice`. But the owner of Models shared with us by `@bob` will
  /// be `@bob`.
  ///
  /// [owner] is set by [Collection] when rehydrating stored data
  final Atsign owner;

  /// the unique identifier which will be prepended to the namespace of the
  /// collection for persistence. For example, if the collection has a
  /// namespace of `tasks.app_1.my_apps` then the full namespace of the
  /// persisted record will be `<id>.tasks.app_1.my_apps`
  ///
  /// [id] is set by [Collection] when rehydrating stored data
  final String id;

  /// The type name; this MUST be included in toJson() and fromJson()
  late final String type;

  /// the application's domain object
  final T obj;

  /// The [Atsign]s with which this data is shared
  final Set<Atsign> sharedWith = {};

  factory Model.domain({
    required Atsign owner,
    required String id,
    required String type,
    required T obj,
    Set<Atsign>? sharedWith,
  }) {
    if (!_factories.containsKey(type)) {
      throw StateError('No factory registered for domain type $type');
    }
    return Model._(
        owner: owner, id: id, type: type, obj: obj, sharedWith: sharedWith);
  }

  factory Model.primitive({
    required Atsign owner,
    required String id,
    required T obj,
    Set<Atsign>? sharedWith,
  }) {
    String type = (obj is Uint8List ? 'binary' : 'n/a');
    return Model._(
        owner: owner, id: id, type: type, obj: obj, sharedWith: sharedWith);
  }

  Model._({
    required this.owner,
    required this.id,
    required this.type,
    required this.obj,
    Set<Atsign>? sharedWith,
  }) {
    if (sharedWith != null) {
      this.sharedWith.addAll(sharedWith);
    }
    if (obj is Uint8List && type != 'binary') {
      throw ArgumentError('factoryType for Uint8List must be "binary"');
    }
  }

  Map<String, dynamic> toJson() {
    if (type == 'binary') {
      return {'type': type, 'obj': Base2e15.encode(obj as Uint8List)};
    } else {
      return {'type': type, 'obj': obj};
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
    return 'Model{owner: $owner, sharedWith: $sharedWith, id: $id, type: $type, obj: $obj}';
  }
}

enum Op { put, delete }

sealed class OpResult {
  /// the atSign for which the operation failed
  final Atsign atSign;
  final Op op;

  OpResult(this.atSign, this.op);
}

class Success extends OpResult {
  Success(super.atSign, super.op);

  @override
  String toString() {
    return '$atSign:${op.name}:Success';
  }
}

class Failure extends OpResult {
  final Object reason;

  Failure(super.atSign, super.op, this.reason);

  @override
  String toString() {
    return '$atSign:${op.name}:Failure:$reason';
  }
}

typedef CollectionGetResponse<T> = ({List<Model<T>> models, List exceptions});

/// Operations to manage objects stored in "collections".
abstract interface class Collection<T> {
  static Collection<T> create<T>(AtClient atClient, String namespace) {
    return CollectionImpl<T>(atClient, namespace);
  }

  /// The [AtClient] we will use
  AtClient get atClient;

  /// The fully qualified namespace. By fully qualified we mean
  /// that the namespace includes the "application namespace".
  ///
  /// i.e. if your application has a namespace of "app_1.my_apps"
  /// and your collection has a namespace of "tasks"
  /// then the full qualified namespace would be "tasks.app_1.my_apps"
  String get namespace;

  /// - saves a copy of [model] for us (aka a 'self' copy)
  /// - saves a copy for each of [Model.sharedWith]
  /// - if [unshareWithOthers] is true, deletes any copies for atSigns who
  ///   are not in [Model.sharedWith]
  /// Returns a stream of [OpResult] for each action taken
  Stream<OpResult> put(
    Model<T> model, {
    bool unshareWithOthers = true,
    required DateTime expiresAt,
    DateTime? availableAt,
  });

  /// Deletes the object.
  /// - If owner was us, also deletes any copies shared with others.
  /// - If owner was other, deletes our cached copy of what was shared with us.
  Stream<OpResult> delete(Model<T> model);

  /// Returns a [CollectionGetResponse] with a model for every unique
  /// `id.collection.namespace@owner`. So for example if `@alice` has shared
  /// the same thing with both `@bob` and `@chuck`, that would be just one
  /// [Model] in the response, with [Model.owner] == `@alice` and
  /// [Model.sharedWith] == `{'@bob','@chuck'}`
  ///
  /// Note that [Model.id] identifiers are treated as unique within collections
  /// for a given [Model.owner] but are not required to be unique across owners.
  ///
  /// Consider example of a `tasks` Collection with a [Model] whose id is
  /// `1` - there may be MANY items in the overall collection with id 1, for
  /// example if `@alice` creates a task with ID 1 and shares it with bob, and
  /// `@bob` creates a task with ID of 1 and shares it with alice, then alice
  /// will have
  /// - `@bob:1.tasks.app_1.my_apps@alice`
  /// - `@alice:1.tasks.app_1.my_apps@bob`
  Future<CollectionGetResponse<T>> get({
    String id,
    Atsign? owner,
  });
}

class CollectionImpl<T> implements Collection<T> {
  /// The [AtClient] we will use
  @override
  final AtClient atClient;

  /// The fully qualified namespace. By fully qualified we mean
  /// that the namespace includes the "application namespace".
  ///
  /// i.e. if your application has a namespace of "app_1.my_apps"
  /// and your collection has a namespace of "tasks"
  /// then the full qualified namespace would be "tasks.app_1.my_apps"
  @override
  final String namespace;

  CollectionImpl(this.atClient, this.namespace) {
    if (!namespace.contains('.')) {
      throw ArgumentError('namespaces must be fully qualified');
    }
  }

  Future<List<AtKey>> getKeys({String? id, Atsign? owner}) async {
    // scan for matching AtKeys
    id ??= '[^.]+';
    String ownerFragment = owner ?? '@';
    final regex = '(^|:)$id\\.$namespace$ownerFragment';

    return (await atClient.getAtKeys(regex: regex))
      ..sort((a, b) => a.fullKeyAndOwner.compareTo(b.fullKeyAndOwner));
  }

  @override
  Future<CollectionGetResponse<T>> get({String? id, Atsign? owner}) async {
    Map<String, Model<T>> map = {};
    List exceptions = [];

    for (final AtKey k in await getKeys(id: id, owner: owner)) {
      try {
        Model<T> m;
        if (map.containsKey(k.fullKeyAndOwner)) {
          m = map[k.fullKeyAndOwner]!;
        } else {
          final AtValue v = await atClient.get(k);
          print('Retrieved raw value ${v.value}');
          final decoded = jsonDecode(v.value!);
          m = Model._(
            owner: k.sharedBy!.toAtsign(),
            id: k.key.split('.').first,
            type: decoded['type'],
            obj: Model.rehydrate<T>(decoded['obj'], decoded['type']),
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
    return (models: map.values.toList(), exceptions: exceptions);
  }

  @override
  Stream<OpResult> put(
    Model<T> model, {
    bool unshareWithOthers = true,
    bool unshare = true,
    required DateTime expiresAt,
    DateTime? availableAt,
  }) async* {
    if (model.owner != atClient.atSign) {
      throw ArgumentError('You may not update models owned by other atSigns');
    }

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

    /// save a copy of [model] for us (aka a 'self' copy) and yield a result
    try {
      AtKey k = AtKey.fromString('${model.id}.$namespace${atClient.atSign}');
      k.metadata = md;
      await atClient.put(
        k,
        jsonEncode(model.toJson()),
      );
      yield Success(atClient.atSign, Op.put);
    } catch (e) {
      yield Failure(atClient.atSign, Op.put, e);
    }

    /// if [unshareWithOthers] is true, deletes any copies for atSigns who
    /// are not in model.sharedWith
    for (final AtKey k in await getKeys(id: model.id, owner: atClient.atSign)) {
      if ((k.sharedWith ?? atClient.atSign) == atClient.atSign) {
        continue;
      }
      await atClient.delete(k);
      yield Success(k.sharedWith!.toAtsign(), Op.delete);
    }

    /// for each item in [shareWith], save a copy for them and yield a result
    for (final otherAtSign in model.sharedWith) {
      try {
        AtKey k = AtKey.fromString(
            '$otherAtSign:${model.id}.$namespace${atClient.atSign}');
        k.metadata = md;
        await atClient.put(
          k,
          jsonEncode(model.toJson()),
        );
        yield Success(otherAtSign, Op.put);
      } catch (e) {
        yield Failure(otherAtSign, Op.put, e);
      }
    }
  }

  @override
  Stream<OpResult> delete(Model<T> model) async* {
    for (final AtKey k in await getKeys(id: model.id, owner: atClient.atSign)) {
      await atClient.delete(k);
      yield Success((k.sharedWith ?? atClient.atSign).toAtsign(), Op.delete);
    }
  }
}
