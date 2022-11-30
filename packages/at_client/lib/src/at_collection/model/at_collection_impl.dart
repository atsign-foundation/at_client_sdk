import 'package:at_client/src/at_collection/model/at_collection_model.dart';
import 'package:at_client/src/at_collection/model/at_collection_spec.dart';
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

  AtCollectionImpl({required this.collectionName});

  @override
  Future<List<T>> getAllData() async {
    /// list = [];
    /// dataMap = getAllDataWithKeys()
    ///
    /// filter all keys which have data and store it in list
    /// return list
    // TODO: implement getAllData
    throw UnimplementedError();
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
  Future<List<String>> getSharedWithList() {
    /// Step 1:
    /// keyExistsInLocal = check if self key exists
    ///
    /// (keyExistsInLocal == false)
    ///     throw KeyNotFoundException
    ///
    /// (keyExistsInLocal == true)
    /// fetch all shared with list
    ///
    /// return list
    ///
    // TODO: implement getSharedWithList
    throw UnimplementedError();
  }

  @override
  Future<bool> notify() {
    // TODO: implement notify
    throw UnimplementedError();
  }

  @override
  Future<T?> save(AtCollectionModel model, {int? expiryTime}) async {
    // TODO: add intent
    // var jsonModel = toJson();
    // print('expiryTime : ${jsonModel['keyId']}');
    // String keyWithCollectionName = jsonModel['keyId'] + '.$this.';

    // AtKey atKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);

    /// check if T.keyId already exists
    /// keyExistsInLocal = check if self key exists
    ///
    /// if(keyExistsInLocal == true)
    /// throw KeyAlreadyExistsException
    ///
    /// if(keyExistsInLocal == false)
    ///
    /// forms self key
    /// try {
    /// result = put(key, value)
    /// }
    /// catch(e){
    /// rethrow(e)
    /// }
    ///

    // TODO: implement save
    throw UnimplementedError();
  }

  @override
  Future<Map<String, AtDataStatus>> delete() {
    /// create intent
    /// Step 1: delete self key
    ///
    /// delete the self key
    ///  result = delete(key)
    ///
    /// if(result == false) {
    ///  throw AtClientException
    /// }
    ///
    /// step 2: get all shared keys List<SharedKey>
    ///
    /// try {

    ///         for(SharedKey key : sharedKeys) {
    ///         atClient.delete(key);
    ///         atDataStatus.put(sharedWithAtsign, key, true);
    ///         }
    /// } catch  (e) {
    ///   atDataStatus.put(sharedWithAtsign, key, e, false);
    /// }
    ///
    /// delete intent
    ///
    /// return atDataStatus

    // TODO: implement delete
    throw UnimplementedError();
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

  /// accepting keyId instead of model to avoid conflict between saved and unsaved key
  ///
  /// TODO: change return type of [share] in specs and imp file
  /// return type of stream based share approach
  /// class ShareOperation {
  ///     ResponseStream<AtDataStatus> stream;
  ///     ShareOperationSummary summary;
  ///     stop();
  /// }

  @override
  Future<Map<String, AtDataStatus>> share(List<String> atSignsList) {
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
    // Step 2: Fetch self key data for keyId, that will be used to share with atSignsList

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

    // TODO: implement share
    throw UnimplementedError();
  }

  @override
  Future<Map<String, AtDataStatus>> unShare(
      String keyId, List<String> atSignsList) {
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

    // TODO: implement share
    throw UnimplementedError();
  }

  @override
  Future<Map<String, AtDataStatus>> update() {
    /// create intent
    /// Step 1: update self key
    ///
    /// update the self key / create if key does not exists
    ///  result = put(key , value)
    ///
    /// if(result == false) {
    ///  throw AtClientException
    /// }
    ///
    /// step 2: get all shared keys List<SharedKey>
    ///
    /// try {

    ///         for(SharedKey key : sharedKeys) {
    ///             atClient.put(key, value);
    ///         atDataStatus.put(sharedWithAtsign, key, true);
    ///         }
    /// } catch  (e) {
    ///   atDataStatus.put(sharedWithAtsign, key, e, false);
    /// }
    ///
    /// delete intent
    ///
    /// return atDataStatus

    // TODO: implement update
    throw UnimplementedError();
  }

  //
  // Future<T?> create(T value) async {
  //   String key = '${Uuid().v4()}.$collectionName';
  //   value.keyId = key;

  //   var atKey = getAtKey(key);

  //   var res = await AtClientManager.getInstance()
  //       .atClient
  //       .put(atKey, jsonEncode(value.toJson()));

  //   return res ? value : null;
  // }

  // Future<bool> update(T value) async {
  //   assert(value.keyId != null, 'keyId can not be null');

  //   var atKey = getAtKey(value.keyId!);

  //   var res = await AtClientManager.getInstance()
  //       .atClient
  //       .put(atKey, jsonEncode(value.toJson()));
  //   return res;
  // }

  // Future<List<T>> getAllData(T Function(String) convert) async {
  //   List<T> allRecords = [];

  //   var records = await AtClientManager.getInstance()
  //       .atClient
  //       .getAtKeys(regex: collectionName);

  //   records.retainWhere((element) => element.sharedWith == null);

  //   for (var key in records) {
  //     var atValue = await AtClientManager.getInstance().atClient.get(key);
  //     var tempModel = convert(atValue.value);
  //     allRecords.add(tempModel);
  //   }
  //   return allRecords;
  // }

  // Future<void> delete(T value) async {
  //   var records = await AtClientManager.getInstance()
  //       .atClient
  //       .getAtKeys(regex: value.keyId);

  //   for (var key in records) {
  //     var res = await AtClientManager.getInstance().atClient.delete(key);
  //     _logger.finer('delete ${key.key}: $res');
  //   }
  // }

  // share(T value, String atSign) async {
  //   assert(value.keyId != null, 'keyId can not be null');

  //   var atKey = getAtKey(value.keyId!, sharedWith: atSign);
  //   var res = await AtClientManager.getInstance()
  //       .atClient
  //       .put(atKey, jsonEncode(value.toJson()));
  // }

  // Future<List<String>> getSharedWithList(T value) async {
  //   List<String> sharedWithList = [];

  //   var records = await AtClientManager.getInstance()
  //       .atClient
  //       .getAtKeys(regex: value.keyId);

  //   records.retainWhere((element) => element.sharedWith != null);
  //   records.forEach((element) {
  //     sharedWithList.add(element.sharedWith!);
  //   });
  //   return sharedWithList;
  // }

  // ///testing
  // deleteAll() async {
  //   var records = await AtClientManager.getInstance()
  //       .atClient
  //       .getAtKeys(regex: collectionName);

  //   for (var key in records) {
  //     var atValue = await AtClientManager.getInstance().atClient.delete(key);
  //   }
  // }

  // getAtKey(String key, {String? sharedWith}) {
  //   return AtKey()
  //     ..key = key
  //     ..namespace = nameSpace
  //     ..metadata = Metadata()
  //     ..metadata!.ttr = -1
  //     ..sharedWith = sharedWith
  //     // file transfer key will be deleted after 15 days

  //     /// TODO : only for testing purpose
  //     ..metadata!.ttl = 1296000000 // 1000 * 60 * 60 * 24 * 15
  //     ..sharedBy = AtClientManager.getInstance().atClient.getCurrentAtSign();
  // }
}

class AtDataStatus {
  late String atSign;
  late String key;
  late bool status;
  AtClientException? exception;
}
