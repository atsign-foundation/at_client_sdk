import 'dart:async';

import 'package:at_client/at_collection/model/at_operation_item_status.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

class DataOperationModel {
  final _logger = AtSignLogger('DataOperationModel');

  AtKey atkey;
  DataOperationModelType dataOperationModelType;
  late DataOperationModelStatus dataOperationModelStatus;

  /// Only needed if dataOperationModelType == ([DataOperationModelType.SAVE] || [DataOperationModelType.SHARE])
  String? jsonEncodedData;

  /// will contain list of all AtOperationItemStatus sent to [atShareOperationStream] till now
  late List<AtOperationItemStatus> allData;

  final StreamController _atShareOperationController =
      StreamController<AtOperationItemStatus>.broadcast();
  Stream<AtOperationItemStatus> get atShareOperationStream =>
      _atShareOperationController.stream as Stream<AtOperationItemStatus>;

  DataOperationModel({
    required this.atkey,
    required this.dataOperationModelType,
    this.jsonEncodedData,
  }) {
    if ((dataOperationModelType == DataOperationModelType.SAVE) ||
        (dataOperationModelType == DataOperationModelType.SHARE)) {
      assert(jsonEncodedData != null);
    }
    allData = [];
    dataOperationModelStatus = DataOperationModelStatus.INPROGRESS;
    _init();
  }

  void emitFromStream(AtOperationItemStatus _event) {
    allData.add(_event);
    _atShareOperationController.sink.add(_event);
  }

  _init() {
    switch (dataOperationModelType) {
      case DataOperationModelType.SAVE:
        _save();
        break;
      case DataOperationModelType.DELETE:
        // TODO: Handle this case.
        break;
      case DataOperationModelType.SHARE:
        // TODO: Handle this case.
        break;
      case DataOperationModelType.UNSHARE:
        // TODO: Handle this case.
        break;
    }
  }

  _save() async {
    assert(jsonEncodedData != null);

    var atDataStatus = AtOperationItemStatus(
        atSign: AtClientManager.getInstance().atClient.getCurrentAtSign()!,
        key: atkey.key!,
        complete: false,
        operation: Operation.save);

    /// update self key
    try {
      var result = await _put(atkey, jsonEncodedData!);
      _logger.finer('model saved: ${atkey.key}');

      atDataStatus.complete = result;
    } catch (e) {
      atDataStatus.complete = false;

      _logger.severe('model update failed: ${atkey.key}');
      rethrow;
    }

    ///  Add to stream
    emitFromStream(atDataStatus);

    unawaited(_updateSharedKeys(atkey.key!, jsonEncodedData!));
  }

  Future<void> _updateSharedKeys(
      String keyWithCollectionName, String _jsonEncodedData) async {
    ///updating shared keys
    var sharedAtKeys = await AtClientManager.getInstance()
        .atClient
        .getAtKeys(regex: keyWithCollectionName);
    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    for (var sharedKey in sharedAtKeys) {
      var atDataStatus = AtOperationItemStatus(
          atSign: sharedKey.sharedWith!,
          key: sharedKey.key!,
          complete: false,
          operation: Operation.share);

      try {
        /// If self key is not updated, we do not update the shared keys
        var res = await _put(
          sharedKey,
          _jsonEncodedData,
        );

        atDataStatus.complete = res;
      } on AtClientException catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = e;
      } catch (e) {
        atDataStatus.complete = false;
        atDataStatus.exception = Exception('Could not update shared key');
      }

      /// Add to stream
      emitFromStream(atDataStatus);
    }

    _checkStatusForSaveOperation(DataOperationModelStatus.COMPLETE);
  }

  void _checkStatusForSaveOperation(
      DataOperationModelStatus _dataOperationModelStatus) {
    dataOperationModelStatus = _dataOperationModelStatus;
  }

  Future<bool> _put(AtKey _atKey, String _jsonEncodedData) async {
    return await AtClientManager.getInstance().atClient.put(
          _atKey,
          _jsonEncodedData,
        );
  }
}

enum DataOperationModelType {
  SAVE,
  DELETE,
  SHARE,
  UNSHARE,
}

enum DataOperationModelStatus {
  INPROGRESS,
  COMPLETE,
  STOPPED,
}
