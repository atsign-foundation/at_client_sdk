import 'dart:convert';

import 'package:at_client/at_client.dart'
    show
        AtClient,
        Model,
        Collection,
        OpResult,
        QueryResponse,
        ModelResponse,
        ErrorResponse,
        Op,
        Success,
        Failure;
import 'package:at_commons/at_commons.dart' show AtKey, AtValue, Metadata;
import 'package:at_commons/atsign.dart';

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

  @override
  Stream<OpResult> put(
    Model<T> model, {
    Set<Atsign>? shareWith,
    Set<Atsign>? unshareWith,
    required DateTime expiresAt,
    DateTime? availableAt,
  }) async* {
    shareWith ??= {};
    unshareWith ??= {};
    if (shareWith.intersection(unshareWith).isNotEmpty) {
      throw ArgumentError('shareWith and unshareWith must not overlap');
    }

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

    /// save a copy of [model] for us (aka a 'self' copy)
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

    /// for each item in [shareWith], save a copy for them
    for (final otherAtSign in shareWith) {
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

    /// - for each item in [unshareWith], deletes their copy (if it exists)
    for (final otherAtSign in unshareWith) {
      try {
        AtKey k = AtKey.fromString(
            '$otherAtSign:${model.id}.$namespace${atClient.atSign}');
        try {
          await atClient.get(k);
          // key exists
          try {
            await atClient.delete(k);
            yield Success(otherAtSign, Op.delete);
          } catch (e) {
            // delete failed
            yield Failure(otherAtSign, Op.delete, e);
          }
        } catch (_) {
          // key doesn't exist, nothing to delete
          yield Success(otherAtSign, Op.delete);
        }
      } catch (e) {
        yield Failure(otherAtSign, Op.delete, e);
      }
    }

    /// Returns a stream of [OpResult] for each action taken
  }

  @override
  Stream<QueryResponse<T>> get({String? id, Atsign? owner}) async* {
    // scan for matching AtKeys
    // TODO look for either our copy, or copy shared with us by others
    id ??= '[^.]+';
    final regex = '(^|:)$id\\.$namespace@';
    final List<AtKey> keys = await atClient.getAtKeys(regex: regex);
    for (final k in keys) {
      try {
        // fetch each one
        final AtValue v = await atClient.get(k);

        // try to inflate from Json and emit a ModelResponse
        final decoded = jsonDecode(v.value!);

        final Model<T> model = Model.fromJson(decoded);
        yield ModelResponse(model);
      } catch (e, st) {
        // catch - emit an ErrorResponse
        yield ErrorResponse(error: e, stackTrace: st);
      }
    }
    return;
  }

  @override
  Future<List<Model<T>>> getList({String? id, Atsign? owner}) async {
    final List<Model<T>> l = [];
    final List exceptions = [];

    await for (final r in get(id: id, owner: owner)) {
      switch (r) {
        case ModelResponse(value: var m):
          l.add(m);
        case ErrorResponse(error: var e):
          exceptions.add(e);
      }
    }
    if (exceptions.isNotEmpty) {
      throw Exception('Some operations failed: $exceptions');
    }
    return l;
  }

  @override
  Stream<OpResult> delete(Model<T> model) async* {}
}
