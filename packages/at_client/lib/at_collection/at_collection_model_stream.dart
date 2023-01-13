import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/collection_methods_impl.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/at_collection_model_stream_spec.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';
import 'package:meta/meta.dart';

/// implementation of [AtCollectionModelStreamSpec]
class AtCollectionModelStream<T> extends AtCollectionModelStreamSpec {
  final _logger = AtSignLogger('AtCollectionModelStream');

  @visibleForTesting
  AtClient? atClient;

  KeyMakerSpec keyMaker = DefaultKeyMaker();

  late AtCollectionModel atCollectionModel;

  AtCollectionModelStream(
      {required this.atCollectionModel, required this.keyMaker});

  @override
  Stream<AtOperationItemStatus> save(
      {bool share = true, ObjectLifeCycleOptions? options}) async* {
    _validateModel();

    yield* CollectionMethodImpl.getInstance().save(
      jsonEncodedData: jsonEncode(atCollectionModel.toJson()),
      options: options,
      share: share,
    );
  }

  @override
  Stream<AtOperationItemStatus> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options}) async* {
    _validateModel();

    yield* CollectionMethodImpl.getInstance().shareWith(
      atSigns,
      jsonEncodedData: jsonEncode(atCollectionModel.toJson()),
      options: options,
    );
  }

  @override
  Stream<AtOperationItemStatus> delete() async* {
    _validateModel();

    yield* CollectionMethodImpl.getInstance().delete();
    yield* CollectionMethodImpl.getInstance().unshare();
  }

  @override
  Stream<AtOperationItemStatus> unshare({List<String>? atSigns}) async* {
    yield* CollectionMethodImpl.getInstance().unshare(atSigns: atSigns);
  }

  /// Throws exception if id or collectionName is not added.
  _validateModel() {
    if (atCollectionModel.id.trim().isEmpty) {
      throw Exception('id not found');
    }

    if (atCollectionModel.getCollectionName().trim().isEmpty) {
      throw Exception('collectionName not found');
    }

    if (atCollectionModel.toJson()['id'] == null) {
      throw Exception('id not added in toJson');
    }

    if (atCollectionModel.toJson()['collectionName'] == null) {
      throw Exception('collectionName not added in toJson');
    }
  }
}
