import 'dart:developer';

import 'package:at_client/at_collection/at_collection_spec.dart';
import 'package:at_client/at_collection/model/at_collection_model.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/data_operation_model.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/util/at_collection_utils.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';

/// implementation of [AtCollectionSpec]
class AtCollectionImpl
  // <T extends AtCollectionModel>
    extends AtCollectionModelSpec {
  final _logger = AtSignLogger('AtCollectionImpl');

  AtCollectionImpl({required collectionName, 
  // required convert
  })
      : super(
          collectionNameParam: collectionName,
          // convert: convert,
          // references: [Address],
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
  DataOperationModel save({bool share = true, ObjectLifeCycleOptions? options}) {
    _validateModel();

    String keyWithCollectionName = '$id.${AtCollectionModelSpec.collectionName}';

    AtKey selKey = AtCollectionUtil.formAtKey(
      key: keyWithCollectionName,
      ttl: options?.timeToLive?.inMilliseconds,
      ttb: options?.timeToBirth?.inMilliseconds,
    );

    print(jsonEncode(toJson()));

    return DataOperationModel(
      atkey: selKey, 
      dataOperationModelType: DataOperationModelType.SAVE, 
      jsonEncodedData: jsonEncode(toJson())
    );
  }

  @override
  DataOperationModel delete() {
    // TODO: implement delete
    throw UnimplementedError();
  }

  // @override
  // fromJSON() {
  //   // TODO: implement fromJSON
  //   throw UnimplementedError();
  // }

  @override
  getId() {
    return id;
  }

  @override
  List<String> getSharedWith() {
    // TODO: implement getSharedWith
    throw UnimplementedError();
  }


  @override
  void setObjectLifeCycleOptions() {
    // TODO: implement setObjectLifeCycleOptions
  }

  @override
  DataOperationModel shareWith(List<String> atSigns, {ObjectLifeCycleOptions? options}) {
    // TODO: implement shareWith
    throw UnimplementedError();
  }

  // @override
  // toJSON() {
  //   // TODO: implement toJSON
  //   throw UnimplementedError();
  // }

  @override
  DataOperationModel unshare({List<String>? atSigns}) {
    // TODO: implement unshare
    throw UnimplementedError();
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
}
