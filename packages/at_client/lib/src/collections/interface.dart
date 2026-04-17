import 'package:at_client/at_client.dart'
    show AtClient, Atsign, AtCollectionModel;
import 'package:at_commons/at_commons.dart';

typedef FromJsonFunction = Object Function(Map<String, dynamic> json);

final class Model<T> {
  static Map<String, FromJsonFunction> factories = {'json': (json) => json};

  /// The atSign which created this Model. For example let's say we are
  /// currently `@alice`; then owners of Models which we create would be
  /// `@alice`. But the owner of Models shared with us by `@bob` will
  /// be `@bob`.
  ///
  /// owner is set by [Collection] when either creating (`put`) new objects
  /// or when fetching objects from atServer or local storage.
  final Atsign owner;

  /// Maintained by Collections
  /// TODO Should be persisted
  final Set<Atsign> sharedWith = {};

  /// the unique identifier which will be prepended to the namespace of the
  /// collection for persistence. For example, if the collection has a
  /// namespace of `tasks.app_1.my_apps` then the full namespace of the
  /// persisted record will be `<id>.tasks.app_1.my_apps`
  final String id;

  /// The type name; this MUST be included in toJson() and fromJson()
  final String type;

  /// the application's domain object
  final T obj;

  Model({
    required this.owner,
    required this.id,
    required this.type,
    required this.obj,
  });

  Map<String, dynamic> toJson() =>
      {'owner': owner, 'id': id, 'type': type, 'obj': obj};

  static Model<T> fromJson<T>(Map<String, dynamic> json) {
    final f = factories[json['type'] ?? 'json'];
    if (f == null) {
      throw ArgumentError('No factory for ${json['type']}');
    }
    final T obj = f.call(json['obj']) as T;
    return Model(
      owner: json['owner'].toString().toAtsign(),
      id: json['id'],
      type: json['type'],
      obj: obj,
    );
  }

  @override
  String toString() {
    return 'Model{owner: $owner, sharedWith: $sharedWith, id: $id, type: $type, obj: $obj}';
  }
}

sealed class QueryResponse<T> {}

class ModelResponse<T> extends QueryResponse<T> {
  final Model<T> value;

  ModelResponse(this.value);

  @override
  String toString() {
    return 'ModelResponse{value: $value}';
  }
}

class ErrorResponse<T> extends QueryResponse<T> {
  final Object error;
  final StackTrace? stackTrace;
  final Object? value;

  ErrorResponse({required this.error, required this.stackTrace, this.value});

  @override
  String toString() {
    return 'ErrorResponse{error: $error, stackTrace: $stackTrace, value: $value}';
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

/// Operations to manage objects stored in "collections".
abstract interface class Collection<T> {
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
  /// - for each item in [shareWith], saves a copy for them
  /// - for each item in [unshareWith], deletes their copy (if it exists)
  ///
  /// Returns a stream of [OpResult] for each action taken
  /// [ArgumentError] if shareWith and unshareWith are not mutually exclusive.
  Stream<OpResult> put(
    Model<T> model, {
    Set<Atsign>? shareWith,
    Set<Atsign>? unshareWith,
    required DateTime expiresAt,
    DateTime? availableAt,
  });

  /// Deletes the object.
  /// - If owner was us, also deletes any copies shared with others.
  /// - If owner was other, deletes our cached copy of what was shared with us.
  Stream<OpResult> delete(Model<T> model);

  /// The stream will contain either [ModelResponse] or [ErrorResponse].
  ///
  /// Individual identifiers are expected to be unique within collections
  /// for a given [Model.owner] but are not required to be unique across owners.
  ///
  /// Consider example of a `tasks` Collection with a [Model] whose id is
  /// `1` - there may be MANY items in the overall collection with id 1, for
  /// example if `@alice` creates a task with ID 1 and shares it with bob, and
  /// `@bob` creates a task with ID of 1 and shares it with alice, then alice
  /// will have
  /// - `@bob:1.tasks.app_1.my_apps@alice`
  /// - `@alice:1.tasks.app_1.my_apps@bob`
  Stream<QueryResponse<T>> get({String id, Atsign? owner});

  /// Calls [get], puts each [ModelResponse.value] in the returned list.
  ///
  /// Throws an exception if there was at least one [ErrorResponse].
  Future<List<Model<T>>> getList({String? id, Atsign? owner});

// TODO Some static queries spanning collections (get everything
// TODO shared by others with me, get everything shared by me with others)
}

/// Contains CRUD operations that can be performed on [AtCollectionModel]
/// Contains query methods on [AtCollectionModel]
// ignore: unused_element
abstract interface class _HideMe {
  Future<List<T>> getModelsSharedBy<T extends AtCollectionModel>(String atSign);

  Future<List<T>> getModelsSharedByAnyAtSign<T extends AtCollectionModel>();

  Future<List<T>> getModelsSharedWith<T extends AtCollectionModel>(
      String atSign);

  Future<List<T>> getModelsSharedWithAnyAtSign<T extends AtCollectionModel>();

  Future<T> getModel<T extends AtCollectionModel>(
      String id, String namespace, String collectionName);

  Future<List<T>> getModelsByCollectionName<T extends AtCollectionModel>(
      String collectionName);
}
