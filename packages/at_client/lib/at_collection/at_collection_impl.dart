import 'package:at_client/at_collection/model/at_collection_model_spec.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/util/at_collection_utils.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';

/// implementation of [AtCollectionModelSpec]
class AtCollectionImpl extends AtCollectionModelSpec {
  final _logger = AtSignLogger('AtCollectionImpl');

  AtCollectionImpl({required collectionName})
      : super(
          collectionNameParam: collectionName,
        );

  static Future<List<Map>> getAllData() async {
    List<Map> dataList = [];

    var collectionAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: AtCollectionModelSpec.collectionName);

    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == null);

    /// TODO: can there be a scenario when key is available but we can't get data
    /// In that scenario we might have to give failure results to app.
    for (var atKey in collectionAtKeys) {
      try {
        var atValue = await AtClientManager.getInstance().atClient.get(atKey);
        dataList.add(jsonDecode(atValue.value));
      } catch (e) {
        print('failed to get value of ${atKey.key}');
      }
    }

    return dataList;
  }

  @override
  save({bool share = true, ObjectLifeCycleOptions? options}) async {
    _validateModel();

    String keyWithCollectionName = '$id.${AtCollectionModelSpec.collectionName}';

    AtKey selfKey = AtCollectionUtil.formAtKey(
      key: keyWithCollectionName,
      ttl: options?.timeToLive?.inMilliseconds,
      ttb: options?.timeToBirth?.inMilliseconds,
    );

    print(jsonEncode(toJson()));

    await _save(selfKey, jsonEncode(toJson()));
    if(share){
      await _updateSharedKeys(selfKey.key!, jsonEncode(toJson()));
    }
  }

  Future<bool> _save(AtKey atkey, String jsonEncodedData) async {
    /// update self key
    try {
      var result = await _put(atkey, jsonEncodedData);
      _logger.finer('model saved: ${atkey.key}');
      return result;
    } catch (e) {
      _logger.severe('model update failed: ${atkey.key}');
      rethrow;
    }
  }

  Future<bool> _updateSharedKeys(String keyWithCollectionName, String _jsonEncodedData) async {
    ///updating shared keys
    var sharedAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: keyWithCollectionName);
    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    bool allOpeartionSuccessful = true;

    for (var sharedKey in sharedAtKeys) {
      try {
        /// If self key is not updated, we do not update the shared keys
        var res = await _put(sharedKey, _jsonEncodedData,);
        if(!res) {
          allOpeartionSuccessful = false;
        }
      } catch (e) {
        allOpeartionSuccessful = false;
        print("Error in deleting $sharedKey $e");
      }
    }

    return allOpeartionSuccessful;
  }


  @override
  Future<List<String>> getSharedWith() async {
    _validateModel();
    List<String> sharedWithList = [];

    var allKeys =
        await AtClientManager.getInstance().atClient.getAtKeys(regex: id);

    for (var atKey in allKeys) {
      if (atKey.sharedWith != null) {
        sharedWithList.add(atKey.sharedWith!);
      }
    }

    return sharedWithList;
  }

  @override
  Future<bool> shareWith(List<String> atSigns, {ObjectLifeCycleOptions? options}) async{
    _validateModel();

    /// create intent
    /// TODO: throw keyNotFoundException when self key is not formed.
    String keyWithCollectionName = '$id.${AtCollectionModelSpec.collectionName}';

    var selfKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);
    bool allOpeartionSuccessful = true;

    for (var atSign in atSigns) {
      var sharedAtKey = selfKey;
      sharedAtKey.sharedWith = atSign;

      try {
        var res = await _put(sharedAtKey, jsonEncode(toJson()));
        if(!res){
            allOpeartionSuccessful = false;
          }
      } catch (e) {
        allOpeartionSuccessful = false;
        print("Error in sharing $atSign $e");
      }
    }
    return allOpeartionSuccessful;
  }

  @override
  Future<bool> delete() async {
    _validateModel();

    String keyWithCollectionName = '$id.${AtCollectionModelSpec.collectionName}';
    AtKey selfAtKey = AtCollectionUtil.formAtKey(key: keyWithCollectionName);

    var isSelfKeyDeleted =
        await AtClientManager.getInstance().atClient.delete(selfAtKey);

    if (!isSelfKeyDeleted) {
      return false;
    }

    return await unshare();
  }

  @override
  Future<bool> unshare({List<String>? atSigns}) async {
    String keyWithCollectionName = '$id.${AtCollectionModelSpec.collectionName}';

    var sharedAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: keyWithCollectionName);

    if(atSigns == null) {
      sharedAtKeys.retainWhere((element) => element.sharedWith != null);
    } else {
      sharedAtKeys.retainWhere((element) => atSigns.contains(element.sharedWith));
    }

    bool allOpeartionSuccessful = true;

    for (var sharedKey in sharedAtKeys) {
      try {
          var res =
              await AtClientManager.getInstance().atClient.delete(sharedKey);

          if(!res){
            allOpeartionSuccessful = false;
          }
      } catch (e) {
        allOpeartionSuccessful = false;
        print("Error in deleting $sharedKey $e");
      }
    }

    return allOpeartionSuccessful;
  }

  @override
  getId() {
    return id;
  }

  @override
  void setObjectLifeCycleOptions() {
    // TODO: implement setObjectLifeCycleOptions
  }
  
  @override
  Map<String, dynamic> toJson() {
    // TODO: implement toJson
    throw UnimplementedError();
  }
  
  /// Throws exception if id or collectionName is not added.
  _validateModel() {
    if (id.trim().isEmpty) {
      throw Exception('id not found');
    }

    if (AtCollectionModelSpec.collectionName.trim().isEmpty) {
      throw Exception('collectionName not found');
    }

    if (toJson()['id'] == null) {
      throw Exception('id not added in toJson');
    }

    if (toJson()['collectionName'] == null) {
      throw Exception('collectionName not added in toJson');
    }
  }

  Future<bool> _put(AtKey _atKey, String _jsonEncodedData) async {
    return await AtClientManager.getInstance().atClient.put(
      _atKey,
      _jsonEncodedData,
    );
  }
}
