import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';
import 'package:meta/meta.dart';

/// implementation of [AtCollectionModelSpec]
class AtCollectionModel extends AtCollectionModelSpec {
  final _logger = AtSignLogger('AtCollectionModel');

  @visibleForTesting
  AtClient? atClient;

  late KeyMakerSpec keyMaker;

  AtCollectionModel({required collectionName})
      : super(
          collectionNameParam: collectionName,
        ){
          keyMaker = DefaultKeyMaker();
        } 

  set setKeyMaker(KeyMakerSpec newKeyMaker){
    keyMaker = newKeyMaker;
  }

  AtClient _getAtClient() {
    atClient ??= AtClientManager.getInstance().atClient;
    return atClient!;
  }

  @override
  Future<bool> save({bool share = true, ObjectLifeCycleOptions? options}) async {
    _validateModel();

    AtKey selfKey = keyMaker.createSelfKey(
      keyId: id,
      collectionName: AtCollectionModelSpec.collectionName,
      objectLifeCycleOptions: options,
    );

    var res = await _save(selfKey, jsonEncode(toJson()));
    if(res && share){
      var update = await _updateSharedKeys(selfKey.key!, jsonEncode(toJson()));
      return update;
    }

    return res;
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

  Future<bool> _updateSharedKeys(String keyWithCollectionName, String jsonEncodedData) async {
    ///updating shared keys
    var sharedAtKeys = await _getAtClient().getAtKeys(regex: keyWithCollectionName);
    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    bool allOpeartionSuccessful = true;

    for (var sharedKey in sharedAtKeys) {
      try {
        /// If self key is not updated, we do not update the shared keys
        var res = await _put(sharedKey, jsonEncodedData,);
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
        await _getAtClient().getAtKeys(regex: 
          '$id.${AtCollectionModelSpec.collectionName}'
        );

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

    var selfKey = keyMaker.createSelfKey(
      keyId: id,
      collectionName: AtCollectionModelSpec.collectionName,
    );
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

    AtKey selfAtKey = keyMaker.createSelfKey(
      keyId: id,
      collectionName: AtCollectionModelSpec.collectionName,
    );

    var isSelfKeyDeleted =
        await _getAtClient().delete(selfAtKey);

    if (!isSelfKeyDeleted) {
      return false;
    }

    return await unshare();
  }

  @override
  Future<bool> unshare({List<String>? atSigns}) async {
    String keyWithCollectionName = '$id.${AtCollectionModelSpec.collectionName}';

    var sharedAtKeys = await _getAtClient()
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
              await _getAtClient().delete(sharedKey);

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

  Future<bool> _put(AtKey atKey, String jsonEncodedData) async {
    return await _getAtClient().put(
      atKey,
      jsonEncodedData,
    );
  }
}
