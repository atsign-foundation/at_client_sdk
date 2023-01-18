import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/collection_methods_impl.dart';
import 'package:at_client/at_collection/collection_util.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/at_collection_model_stream_spec.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';

/// implementation of [AtCollectionModelStreamSpec]
class AtCollectionModelStream<T> extends AtCollectionModelStreamSpec {
  final _logger = AtSignLogger('AtCollectionModelStream');

  KeyMakerSpec keyMaker = DefaultKeyMaker();

  late AtCollectionModel atCollectionModel;

  AtCollectionModelStream(
      {required this.atCollectionModel, required this.keyMaker});

  @override
  Stream<AtOperationItemStatus> save(
      {bool share = true, ObjectLifeCycleOptions? options}) async* {
    var jsonObject = _initAndValidateJson();

    yield* CollectionMethodImpl.getInstance().save(
      jsonEncodedData: jsonEncode(jsonObject),
      options: options,
      share: share,
    );
  }

  @override
  Stream<AtOperationItemStatus> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options}) async* {
    var jsonObject = _initAndValidateJson();

    yield* CollectionMethodImpl.getInstance().shareWith(
      atSigns,
      jsonEncodedData: jsonEncode(jsonObject),
      options: options,
    );
  }

  @override
  Stream<AtOperationItemStatus> delete() async* {
    _initAndValidateJson();

    yield* CollectionMethodImpl.getInstance().delete();
    yield* CollectionMethodImpl.getInstance().unshare();
  }

  @override
  Stream<AtOperationItemStatus> unshare({List<String>? atSigns}) async* {
    yield* CollectionMethodImpl.getInstance().unshare(atSigns: atSigns);
  }

  Map<String, dynamic> _initAndValidateJson() {
    Map<String, dynamic> objectJson = atCollectionModel.toJson();
    objectJson['id'] = atCollectionModel.id;
    objectJson['collectionName'] = atCollectionModel.getCollectionName();
    CollectionUtil.validateModel(
      modelJson: objectJson,
      id: atCollectionModel.id,
      collectionName: atCollectionModel.getCollectionName(),
    );
    return objectJson;
  }
}
