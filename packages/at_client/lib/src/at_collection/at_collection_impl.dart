import 'dart:developer';

import 'package:at_client/src/at_collection/at_collection_spec.dart';
import 'package:at_client/src/at_collection/model/at_collection_model.dart';
import 'package:at_client/src/at_collection/model/at_operation_item_status.dart';
import 'package:at_client/src/at_collection/model/at_share_operation.dart';
import 'package:at_client/src/at_collection/model/at_unshare_operation.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/util/at_collection_utils.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';

/// implementation of [AtCollectionSpec]
class AtCollectionImpl<T extends AtCollectionModel>
    implements AtCollectionSpec {
  final _logger = AtSignLogger('AtCollectionImpl');

  /// [collectionName] is a unique name that is given to a class that extends [AtCollectionModel].
  ///
  /// For Each instance of [AtCollectionImpl], [T] and [collectionName] are unique.
  late String collectionName;

  /// [convert] is function that accepts json encoded [String] and forms an instance of [AtCollectionModel].
  final T Function(String encodedString) convert;

  late String _currentAtsign;
  late AtClient _atCLient;

  AtCollectionImpl({required this.collectionName, required this.convert}) {
    _currentAtsign = AtClientManager.getInstance().atClient.getCurrentAtSign()!;
    _atCLient = AtClientManager.getInstance().atClient;
  }

  @override
  Future<List<T>> getAllData() async {
    List<T> dataList = [];

    var collectionAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: collectionName);

    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == null);

    /// TODO: can there be a scenario when key is available but we can't get data
    /// In that scenario we might have to give failure results to app.
    for (var atKey in collectionAtKeys) {
      try {
        var atValue = await AtClientManager.getInstance().atClient.get(atKey);
        var data = convert(atValue.value);
        dataList.add(data);
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }

    return dataList;
  }

  @override
  Future<T> getById(String id, {String? sharedWith}) async {
    AtKey atKey = AtCollectionUtil.formAtKey(
      key: '$id.$collectionName',
      sharedWith: sharedWith,
    );

    try {
      AtValue atValue = await AtClientManager.getInstance().atClient.get(atKey);

      var modelData = convert(atValue.value);
      return modelData;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, AtCollectionModel>> _getAllDataWithKeys(
      AtCollectionModel Function(String p1) convert) {
    /// fetchStatus = {};
    /// getAllKeys with collectionName
    /// filter out all the self keys
    ///
    /// for(selfKey in selfKeys){
    /// try{
    /// value = atCLient.get(selfKey)
    /// fetchStatus[selfKey] = value;
    /// }
    /// catch(e){
    /// fetchStatus[selfKey] = e;
    /// }
    ///
    ///  return fetchStatus;
    /// }
    ///
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getSharedWithList(AtCollectionModel model) async {
    _validateModel(model);
    List<String> sharedWithList = [];

    var allKeys =
        await AtClientManager.getInstance().atClient.getAtKeys(regex: model.id);

    for (var atKey in allKeys) {
      if (atKey.sharedWith != null) {
        sharedWithList.add(atKey.sharedWith!);
      }
    }

    return sharedWithList;
  }

  @override
  Future<bool> save(AtCollectionModel model, {int? expiryTime}) async {
    _validateModel(model);

    String keyWithCollectionName = '${model.id}.${model.collectionName}';

    AtKey selKey = AtCollectionUtil.formAtKey(
      key: keyWithCollectionName,
      ttl: expiryTime,
    );

    /// throws exception If key already exists
    try {
      var atvalue = await AtClientManager.getInstance().atClient.get(selKey);
      if (atvalue.value != null) {
        throw Exception('${model.id} is already saved.');
      }
    } catch (e) {
      /// If some exceptions happens, key does not exists in keystore.
    }

    var result = false;
    try {
      result = await AtClientManager.getInstance().atClient.put(
            selKey,
            jsonEncode(model.toJson()),
          );

      _logger.finer('model saved: ${model.id}');
      return result;
    } catch (e) {
      _logger.severe('model update failed: ${model.id}');
      rethrow;
    }
  }

  @override
  Future<List<AtOperationItemStatus>> delete(AtCollectionModel model) async {
    _validateModel(model);

    /// create intent

    /// Step 1: delete self key
    List<AtOperationItemStatus> atDataStatusList = [];

    String keyWithCollectionName = '${model.id}.${model.collectionName}';
    AtKey selfAtKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);

    var isSelfKeyDeleted =
        await AtClientManager.getInstance().atClient.delete(selfAtKey);
    var selfKeyDeleteStatus = AtOperationItemStatus(
      atSign: _currentAtsign,
      key: keyWithCollectionName,
      complete: isSelfKeyDeleted,
    );

    atDataStatusList.add(selfKeyDeleteStatus);

    var sharedAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: keyWithCollectionName);
    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    for (var sharedKey in sharedAtKeys) {
      var atDataStatus = AtOperationItemStatus(
        atSign: sharedKey.sharedWith!,
        key: sharedKey.key!,
        complete: null,
      );

      try {
        if (isSelfKeyDeleted) {
          var res =
              await AtClientManager.getInstance().atClient.delete(sharedKey);

          atDataStatus.complete = res;
        }
      } on AtClientException catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = e;
      } catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = Exception('Could not update shared key');
      }
      atDataStatusList.add(atDataStatus);
    }

    /// delete intent
    return atDataStatusList;
  }

  @override
  AtShareOperation share(AtCollectionModel model, List<String> atSignsList) {
    _validateModel(model);

    /// create intent
    /// TODO: throw keyNotFoundException when self key is not formed.
    String keyWithCollectionName = '${model.id}.${model.collectionName}';

    var selfKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);
    return AtShareOperation(
      jsonEncodedData: jsonEncode(model.toJson()),
      atSignsList: atSignsList,
      selfAtKey: selfKey,
    );

    /// create intent
    /// Map<String, AtOperationItemStatus> atDataStatus = {};

    /// Step 1:
    /// keyExistsInLocal = check if self key exists in hive
    ///
    /// (keyExistsInLocal == false)
    ///  delete intent
    ///     throw KeyNotFoundException
    ///

    /// if(keyExistsInLocal)
    // Step 2: Fetch self key data for id, that will be used to share with atSignsList

    /// step 3:
    ///
    /// for(atSign in atSignsList) {
    ///         create shared key - if fails :   atDataStatus.put(atSign, key, e, false);
    ///
    ///         atClient.put(sharedKey, value);
    ///         atDataStatus.put(atSign, sharedKey, true);
    ///         }
    ///         catch(e){
    ///          atDataStatus.put(atSign, key, e, false);
    /// }
    ///
    /// delete intent
    /// returns atDataStatus
  }

  @override
  AtUnshareOperation unShare(
      AtCollectionModel model, List<String> atSignsList) {
    _validateModel(model);

    /// create intent
    String keyWithCollectionName = '${model.id}.${model.collectionName}';

    var selfKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);
    return AtUnshareOperation(selfKey: selfKey, atSignsList: atSignsList);

    /// create intent
    /// Map<String, AtOperationItemStatus> atDataStatus = {};

    /// Step 1:
    /// keyExistsInLocal = check if self key exists in hive
    ///
    /// (keyExistsInLocal == false)
    ///     throw KeyNotFoundException
    ///

    /// if(keyExistsInLocal)
    // Step 2: Fetch all shared keys and filter out the ones in atSignsList

    /// step 3:
    ///
    /// for(sharedKey in filteredSharedKeys) {
    ///         atClient.delete(sharedKey, value);
    ///         atDataStatus.put(atSign, sharedKey, true);
    ///         }
    ///         catch(e){
    ///          atDataStatus.put(atSign, key, e, false);
    /// }
    ///
    /// delete intent
    /// returns atDataStatus
  }

  @override
  Future<List<AtOperationItemStatus>> update(AtCollectionModel model,
      {int? expiryTime}) async {
    _validateModel(model);

    ///TODO: add intent
    List<AtOperationItemStatus> atDataStatusList = [];
    String keyWithCollectionName = '${model.id}.${model.collectionName}';

    /// updates the self key
    var isSelfKeyUpdated = await save(model, expiryTime: expiryTime);
    var selfKeyUpdateStatus = AtOperationItemStatus(
      atSign: _currentAtsign,
      key: keyWithCollectionName,
      complete: isSelfKeyUpdated,
    );

    atDataStatusList.add(selfKeyUpdateStatus);

    ///updating shared keys
    var sharedAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: keyWithCollectionName);
    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    for (var sharedKey in sharedAtKeys) {
      var atDataStatus = AtOperationItemStatus(
        atSign: sharedKey.sharedWith!,
        key: sharedKey.key!,
        complete: null,
      );

      try {
        /// If self key is not updated, we do not update the shared keys
        if (isSelfKeyUpdated) {
          var res = await AtClientManager.getInstance().atClient.put(
                sharedKey,
                jsonEncode(model.toJson()),
              );

          atDataStatus.complete = res;
        }
      } on AtClientException catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = e;
      } catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = Exception('Could not update shared key');
      }
      atDataStatusList.add(atDataStatus);
    }

    /// delete intent
    return atDataStatusList;
  }

  /// Throws exception if id or collectionName is not added.
  _validateModel(AtCollectionModel model) {
    if (model.id.trim().isEmpty) {
      throw Exception('id not found');
    }

    if (model.collectionName.trim().isEmpty) {
      throw Exception('collectionName not found');
    }

    if (model.toJson()['id'] == null) {
      throw Exception('id not added in toJson');
    }

    if (model.toJson()['collectionName'] == null) {
      throw Exception('collectionName not added in toJson');
    }
  }
}
