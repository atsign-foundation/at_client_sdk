import 'dart:developer';

import 'package:at_client/src/at_collection/model/at_collection_model.dart';
import 'package:at_client/src/at_collection/model/at_collection_spec.dart';
import 'package:at_client/src/at_collection/model/at_share_operation.dart';
import 'package:at_client/src/at_collection/model/at_unshare_operation.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/util/at_collection_utils.dart';
import 'package:at_utils/at_logger.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';

class AtCollectionImpl<T extends AtCollectionModel>
    implements AtCollectionSpec {
  final _logger = AtSignLogger('AtCollectionImpl');
  late String collectionName;

  /// convert is similar to fromJson, this is used to convert encoded string to object model
  final T Function(String encodedString) convert;

  AtCollectionImpl({required this.collectionName, required this.convert});

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
    AtKey selKey = AtCollectionUtil.formAtKey(
      key: '$id.$collectionName',
      sharedWith: sharedWith,
    );

    try {
      var atValue = await AtClientManager.getInstance().atClient.get(selKey);
      var modelData = convert(atValue.value);
      return modelData;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, AtCollectionModel>> getAllDataWithKeys(
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
    String keyWithCollectionName = '${model.id}.${model.collectionName}';

    AtKey selKey = AtCollectionUtil.formAtKey(
      key: keyWithCollectionName,
      ttl: expiryTime,
    );

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
  Future<List<AtDataStatus>> delete(AtCollectionModel model) async {
    /// create intent

    /// Step 1: delete self key
    List<AtDataStatus> atDataStatus = [];

    String keyWithCollectionName = '${model.id}.${model.collectionName}';
    AtKey selfAtKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);

    var res = await AtClientManager.getInstance().atClient.delete(selfAtKey);

    if (!res) {
      /// delete intent
      return atDataStatus;
    }

    var sharedAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: keyWithCollectionName);
    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    for (var sharedKey in sharedAtKeys) {
      late AtDataStatus atDataStatus = AtDataStatus(
        atSign: sharedKey.sharedWith!,
        key: sharedKey.key!,
        complete: false,
      );

      try {
        var res =
            await AtClientManager.getInstance().atClient.delete(sharedKey);

        atDataStatus.complete = res;
      } on AtClientException catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = e;
      } catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = Exception('Could not update shared key');
      }
    }

    /// delete intent
    return atDataStatus;
  }

  // Time complexity of share:
  // ---------------------------
  // Awaiting on share is tricky. Time it takes for the share depends on following parameters:
  // 1. Number of atsigns
  // 2. Atsigns whose publick keys are already cached vs the ones requiring a look on remote secondary
  // 3. Socket issues that might result in delays (TCP/IP) - Late but happens
  // 4. Network timeout - Late and does not happen

  // alternate return types
  //  Map<String, AtException>
  //  List<ShareFailure>
  //  List<AllStatusObject>

  // Future<void> share(data, List<String> atSigns, ResponseStream stream) {

  // 	N

  // 	try {
  // 	i = 1.. N
  // 		stream.convey(AtSign i successful);

  // 	catch() {
  // 		stream.convey(AtSign i fail);
  // 	}
  // }

  /// accepting id instead of model to avoid conflict between saved and unsaved key
  ///
  /// TODO: change return type of [share] in specs and imp file
  /// return type of stream based share approach
  /// class ShareOperation {
  ///     ResponseStream<AtDataStatus> stream;
  ///     ShareOperationSummary summary;
  ///     stop();
  /// }

  /// For eg.
  /// var _newAtShareOperation = myModelAtCollectionImpl.share(data, ['@kevin', '@colin']);
  ///  _newAtShareOperation.atShareOperationStream.listen((atDataStatusEvent) {
  ///    /// current operation
  ///    print("${atDataStatusEvent.atSign}: ${atDataStatusEvent.status}");

  ///    /// to check if it is completed
  ///    if(_newAtShareOperation.atShareOperationStatus == AtShareOperationStatus.COMPLETE){
  ///      /// complete
  ///    }

  ///    /// all data till now
  ///    for(var _data in _newAtShareOperation.allData){
  ///      print("${_data.atSign}: ${_data.status}");
  ///    }
  ///  });
  ///
  ///  // to stop further shares
  ///  _newAtShareOperation.stop();

  @override
  AtShareOperation share(AtCollectionModel model, List<String> atSignsList) {
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
    /// Map<String, AtDataStatus> atDataStatus = {};

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
    /// create intent
    String keyWithCollectionName = '${model.id}.${model.collectionName}';

    var selfKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);
    return AtUnshareOperation(selfKey: selfKey, atSignsList: atSignsList);

    /// create intent
    /// Map<String, AtDataStatus> atDataStatus = {};

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
  Future<List<AtDataStatus>> update(AtCollectionModel model,
      {int? expiryTime}) async {
    /// add intent
    List<AtDataStatus> atDataStatus = [];
    String keyWithCollectionName = '${model.id}.${model.collectionName}';

    /// updates the self key
    var isSelfKeyUpdated = await save(model, expiryTime: expiryTime);
    if (!isSelfKeyUpdated) {
      /// delete intent
      return atDataStatus;
    }

    ///updating shared keys
    var sharedAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: keyWithCollectionName);
    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    for (var sharedKey in sharedAtKeys) {
      late AtDataStatus atDataStatus = AtDataStatus(
        atSign: sharedKey.sharedWith!,
        key: sharedKey.key!,
        complete: false,
      );

      try {
        var res = await AtClientManager.getInstance().atClient.put(
              sharedKey,
              jsonEncode(model.toJson()),
            );

        atDataStatus.complete = res;
      } on AtClientException catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = e;
      } catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = Exception('Could not update shared key');
      }
    }

    /// delete intent
    return atDataStatus;
  }
}

class AtDataStatus {
  late String atSign;
  late String key;
  late bool complete;
  Exception? exception;

  AtDataStatus({
    required this.atSign,
    required this.key,
    required this.complete,
    this.exception,
  });
}
