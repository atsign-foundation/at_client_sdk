import 'package:at_client/src/at_collection/model/at_collection_model.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_utils/at_logger.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';

class AtCollectionController<T extends AtCollectionModel> {
  final String nameSpace;
  final String collectionName;
  final _logger = AtSignLogger('AtCollectionController');

  AtCollectionController(
      {required this.nameSpace, required this.collectionName});

  /// TODO: add option to accept ttl
  Future<T?> create(T value) async {
    String key = '${Uuid().v4()}.$collectionName';
    value.keyId = key;

    var atKey = getAtKey(key);

    var res = await AtClientManager.getInstance()
        .atClient
        .put(atKey, jsonEncode(value.toJson()));

    return res ? value : null;
  }

  Future<bool> update(T value) async {
    assert(value.keyId != null, 'keyId can not be null');

    var atKey = getAtKey(value.keyId!);

    var res = await AtClientManager.getInstance()
        .atClient
        .put(atKey, jsonEncode(value.toJson()));
    return res;
  }

  Future<List<T>> getAllData(T Function(String) convert) async {
    List<T> allRecords = [];

    var records = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: collectionName);

    records.retainWhere((element) => element.sharedWith == null);

    for (var key in records) {
      var atValue = await AtClientManager.getInstance().atClient.get(key);
      var tempModel = convert(atValue.value);
      allRecords.add(tempModel);
    }
    return allRecords;
  }

  delete(T value) async {
    var records = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: value.keyId);

    for (var key in records) {
      var res = await AtClientManager.getInstance().atClient.delete(key);
      _logger.finer('delete ${key.key}: $res');
    }
  }

  share(T value, String atSign) async {
    assert(value.keyId != null, 'keyId can not be null');

    var atKey = getAtKey(value.keyId!, sharedWith: atSign);
    var res = await AtClientManager.getInstance()
        .atClient
        .put(atKey, jsonEncode(value.toJson()));
  }

  Future<List<String>> getSharedWithList(T value) async {
    List<String> sharedWithList = [];

    var records = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: value.keyId);

    records.retainWhere((element) => element.sharedWith != null);
    records.forEach((element) {
      sharedWithList.add(element.sharedWith!);
    });
    return sharedWithList;
  }

  ///testing
  deleteAll() async {
    var records = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: collectionName);

    for (var key in records) {
      var atValue = await AtClientManager.getInstance().atClient.delete(key);
    }
  }

  getAtKey(String key, {String? sharedWith}) {
    return AtKey()
      ..key = key
      ..namespace = nameSpace
      ..metadata = Metadata()
      ..metadata!.ttr = -1
      ..sharedWith = sharedWith
      // file transfer key will be deleted after 15 days

      /// TODO : only for testing purpose
      ..metadata!.ttl = 1296000000 // 1000 * 60 * 60 * 24 * 15
      ..sharedBy = AtClientManager.getInstance().atClient.getCurrentAtSign();
  }
}
