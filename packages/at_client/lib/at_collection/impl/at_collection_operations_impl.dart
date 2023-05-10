import 'dart:async';
import 'dart:convert';

import 'package:at_utils/at_logger.dart';
import '../../at_client.dart';
import '../collection_util.dart';
import '../collections.dart';
import 'default_key_maker.dart';
import 'collection_methods_impl.dart';

class AtCollectionModelOperationsImpl
    extends AtCollectionModelOperations {
  final _logger = AtSignLogger('AtCollectionModelOperationsImpl');
  final KeyMaker _keyMaker = DefaultKeyMaker();
  late AtCollectionModel atCollectionModel;
  late AtCollectionMethodImpl collectionMethodImpl;

  AtCollectionModelOperationsImpl(this.atCollectionModel) {
    collectionMethodImpl = AtCollectionMethodImpl(atCollectionModel);
  }

  @override
  Future<bool> save(
      {bool autoReshare = true, ObjectLifeCycleOptions? options}) async {

    var jsonObject = CollectionUtil.initAndValidateJson(
        collectionModelJson: toJson(),
        id: atCollectionModel.id,
        collectionName: atCollectionModel.collectionName,
        namespace: atCollectionModel.namespace);

    final Completer<bool> completer = Completer<bool>();

    bool? isSelfKeySaved, isAllKeySaved = true;

    await collectionMethodImpl
        .save(
            jsonEncodedData: jsonEncode(jsonObject),
            options: options,
            share: autoReshare)
        .forEach((AtOperationItemStatus atOperationItemStatus) {
      /// save will update self key as well as the shared keys
      /// the first event that will be coming in the stream would be the AtOperationItemStatus of selfKey
      isSelfKeySaved ??= atOperationItemStatus.complete;

      if (atOperationItemStatus.complete == false) {
        isAllKeySaved = false;
      }
    });

    if (autoReshare == false) {
      completer.complete(isSelfKeySaved);
      return isSelfKeySaved ?? false;
    }

    completer.complete(isAllKeySaved);
    return completer.future;
  }

  @override
  Future<List<String>> sharedWith() async {
    CollectionUtil.checkForNullOrEmptyValues(
        atCollectionModel.id, atCollectionModel.collectionName, atCollectionModel.namespace);

    List<String> sharedWithList = [];
    String formattedId = CollectionUtil.format(atCollectionModel.id);
    String formattedCollectionName =
        CollectionUtil.format(atCollectionModel.collectionName);

    var allKeys = await _getAtClient().getAtKeys(
        regex: CollectionUtil.makeRegex(
            formattedId: formattedId,
            collectionName: formattedCollectionName,
            namespace: atCollectionModel.namespace));

    for (var atKey in allKeys) {
      if (atKey.sharedWith != null) {
        _logger.finest('Adding shared with of $atKey');
        sharedWithList.add(atKey.sharedWith!);
      }
    }

    return sharedWithList;
  }

  @override
  Future<bool> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options}) async {
    var jsonObject = CollectionUtil.initAndValidateJson(
        collectionModelJson: toJson(),
        id: atCollectionModel.id,
        collectionName: atCollectionModel.collectionName,
        namespace: atCollectionModel.namespace);

    List<AtOperationItemStatus> allSharedKeyStatus = [];
    await collectionMethodImpl
        .shareWith(atSigns,
            jsonEncodedData: jsonEncode(jsonObject), options: options)
        .forEach((element) {
      allSharedKeyStatus.add(element);
    });

    bool allOpeartionSuccessful = true;
    for (var sharedKeyStatus in allSharedKeyStatus) {
      if (sharedKeyStatus.complete == false) {
        allOpeartionSuccessful = false;
        break;
      }
    }
    return allOpeartionSuccessful;
  }

  @override
  Future<bool> delete() async {
    CollectionUtil.checkForNullOrEmptyValues(
        atCollectionModel.id, atCollectionModel.collectionName, atCollectionModel.namespace);

    bool isSelfKeyDeleted = false;
    await collectionMethodImpl
        .delete()
        .forEach((AtOperationItemStatus operationEvent) {
      if (operationEvent.complete) {
        isSelfKeyDeleted = true;
      }
    });

    if (!isSelfKeyDeleted) {
      return false;
    }

    /// unsharing all shared keys.
    bool isAllShareKeysUnshared = true;

    await collectionMethodImpl
        .unshare()
        .forEach((AtOperationItemStatus operationEvent) {
      if (operationEvent.complete == false) {
        isAllShareKeysUnshared = false;
      }
    });

    return isAllShareKeysUnshared;
  }

  @override
  Future<bool> unshare({List<String>? atSigns}) async {
    bool isAllShareKeysUnshared = true;

    await collectionMethodImpl
        .unshare(atSigns: atSigns)
        .forEach((AtOperationItemStatus operationEvent) {
      if (operationEvent.complete == false) {
        isAllShareKeysUnshared = false;
      }
    });

    return isAllShareKeysUnshared;
  }

  AtClient _getAtClient() {
    return AtClientManager.getInstance().atClient;
  }

  @override
  fromJson(String jsonObject) {
    return atCollectionModel.fromJson(jsonObject);
  }

  @override
  Map<String, dynamic> toJson() {
    return atCollectionModel.toJson();
  }
}
