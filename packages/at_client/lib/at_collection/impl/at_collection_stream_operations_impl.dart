import 'dart:convert';

import 'package:at_client/at_collection/collections.dart';
import 'package:at_utils/at_logger.dart';

import '../../at_client.dart';
import 'collection_methods_impl.dart';
import '../collection_util.dart';
import 'default_key_maker.dart';

class AtCollectionModelStreamOperationsImpl
    extends AtCollectionModelStreamOperations {
  final _logger = AtSignLogger('AtCollectionModelStreamOperationsImpl');
  final KeyMaker _keyMaker = DefaultKeyMaker();
  late AtCollectionModel atCollectionModel;
  late AtCollectionMethodImpl _collectionMethodImpl;

  AtCollectionModelStreamOperationsImpl(this.atCollectionModel) {
    _collectionMethodImpl = AtCollectionMethodImpl(atCollectionModel);
  }

  @override
  Stream<AtOperationItemStatus> save(
      {bool share = true, ObjectLifeCycleOptions? options}) async* {
    var jsonObject = CollectionUtil.initAndValidateJson(
        collectionModelJson: atCollectionModel.toJson(),
        id: atCollectionModel.id,
        collectionName: atCollectionModel.collectionName,
        namespace: atCollectionModel.namespace);

    yield* _collectionMethodImpl.save(
      jsonEncodedData: jsonEncode(jsonObject),
      options: options,
      share: share,
    );
  }

  @override
  Stream<AtOperationItemStatus> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options}) async* {
    var jsonObject = CollectionUtil.initAndValidateJson(
        collectionModelJson: atCollectionModel.toJson(),
        id: atCollectionModel.id,
        collectionName: atCollectionModel.collectionName,
        namespace: atCollectionModel.namespace);

    yield* _collectionMethodImpl.shareWith(
      atSigns,
      jsonEncodedData: jsonEncode(jsonObject),
      options: options,
    );
  }

  @override
  Stream<AtOperationItemStatus> delete() async* {
    CollectionUtil.checkForNullOrEmptyValues(atCollectionModel.id,
        atCollectionModel.collectionName, atCollectionModel.namespace);

    yield* _collectionMethodImpl.delete();
    yield* _collectionMethodImpl.unshare();
  }

  @override
  Stream<AtOperationItemStatus> unshare({List<String>? atSigns}) async* {
    yield* _collectionMethodImpl.unshare(atSigns: atSigns);
  }
}
