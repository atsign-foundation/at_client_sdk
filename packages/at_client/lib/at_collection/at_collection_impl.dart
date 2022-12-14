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
          collectionName: 'my_collection',
          // convert: convert,
          // references: [Address],
        );

  @override
  DataOperationModel save({bool share = true, ObjectLifeCycleOptions? options}) {
    _validateModel();

    String keyWithCollectionName = '$id.$collectionName';

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

  @override
  fromJSON() {
    // TODO: implement fromJSON
    throw UnimplementedError();
  }

  @override
  getId() {
    // TODO: implement getId
    throw UnimplementedError();
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

  @override
  toJSON() {
    // TODO: implement toJSON
    throw UnimplementedError();
  }

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

    if (collectionName.trim().isEmpty) {
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
