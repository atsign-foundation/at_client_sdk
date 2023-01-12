import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/at_collection_model_stream.dart';
import 'package:at_client/at_collection/at_collection_repository.dart';
import 'package:at_client/at_collection/collection_methods_impl.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';
import 'package:meta/meta.dart';

/// implementation of [AtCollectionModelSpec]
abstract class AtCollectionModel<T> extends AtCollectionModelSpec {
  final _logger = AtSignLogger('AtCollectionModel');

  @visibleForTesting
  AtClient? atClient;

  static KeyMakerSpec keyMaker = DefaultKeyMaker();

  late AtCollectionModelStream streams = AtCollectionModelStream(
    atCollectionModel: this,
    keyMaker: keyMaker,
  );

  static AtCollectionRepository atCollectionRepository = AtCollectionRepository(
    keyMaker: keyMaker,
  );

  AtCollectionModel() {
    CollectionMethodImpl.getInstance().atCollectionModel = this;
  }

  set setKeyMaker(KeyMakerSpec newKeyMaker) {
    keyMaker = newKeyMaker;
    CollectionMethodImpl.getInstance().keyMaker = keyMaker;
  }

  AtClient _getAtClient() {
    atClient ??= AtClientManager.getInstance().atClient;
    return atClient!;
  }

  static Future<T> getById<T extends AtCollectionModel>(String keyId,
      {required String collectionName,
      required AtCollectionModelFactory collectionModelFactory}) async {
    return (await atCollectionRepository.getById<T>(
      keyId,
      collectionName: collectionName,
      collectionModelFactory: collectionModelFactory,
    ));
  }

  static Future<List<T>> getAll<T extends AtCollectionModel>(
      {required String collectionName,
      required AtCollectionModelFactory collectionModelFactory}) async {
    return (await atCollectionRepository.getAll<T>(
      collectionName: collectionName,
      collectionModelFactory: collectionModelFactory,
    ));
  }

  @override
  Future<bool> save(
      {bool share = true, ObjectLifeCycleOptions? options}) async {
    _validateModel();
    final Completer<bool> completer = Completer<bool>();

    bool? isSelfKeySaved, isAllKeySaved = true;

    await CollectionMethodImpl.getInstance()
        .save(
            jsonEncodedData: jsonEncode(toJson()),
            options: options,
            share: share)
        .forEach((AtOperationItemStatus atOperationItemStatus) {
      /// save will update self key as well as the shared keys
      /// the first event that will be coming in the stream would be the AtOperationItemStatus of selfKey
      isSelfKeySaved ??= atOperationItemStatus.complete;

      if (atOperationItemStatus.complete == false) {
        isAllKeySaved = false;
      }
    });

    if (share == false) {
      completer.complete(isSelfKeySaved);
    }

    completer.complete(isAllKeySaved);
    return completer.future;
  }

  @override
  Future<List<String>> getSharedWith() async {
    _validateModel();
    List<String> sharedWithList = [];

    var allKeys =
        await _getAtClient().getAtKeys(regex: '$id.${getCollectionName()}');

    for (var atKey in allKeys) {
      if (atKey.sharedWith != null) {
        sharedWithList.add(atKey.sharedWith!);
      }
    }

    return sharedWithList;
  }

  @override
  Future<bool> shareWith(List<String> atSigns,
      {ObjectLifeCycleOptions? options}) async {
    _validateModel();

    List<AtOperationItemStatus> allSharedKeyStatus = [];
    await CollectionMethodImpl.getInstance()
        .shareWith(atSigns,
            jsonEncodedData: jsonEncode(toJson()), options: options)
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
    _validateModel();

    bool isSelfKeyDeleted = false;
    await CollectionMethodImpl.getInstance()
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

    await CollectionMethodImpl.getInstance()
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

    await CollectionMethodImpl.getInstance()
        .unshare(atSigns: atSigns)
        .forEach((AtOperationItemStatus operationEvent) {
      if (operationEvent.complete == false) {
        isAllShareKeysUnshared = false;
      }
    });

    return isAllShareKeysUnshared;
  }

  @override
  getId() {
    return id;
  }

  /// Throws exception if id or collectionName is not added.
  _validateModel() {
    if (id.trim().isEmpty) {
      throw Exception('id not found');
    }

    if (getCollectionName().trim().isEmpty) {
      throw Exception('collectionName not found');
    }

    if (toJson()['id'] == null) {
      throw Exception('id not added in toJson');
    }

    if (toJson()['collectionName'] == null) {
      throw Exception('collectionName not added in toJson');
    }
  }

  Future<bool> _put(AtKey atKey, String jsonEncodedData) async {
    return await _getAtClient().put(
      atKey,
      jsonEncodedData,
    );
  }
}
