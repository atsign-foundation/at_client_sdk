import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/at_collection/at_collection_impl.dart';
import 'package:at_client/src/at_collection/model/at_operation_item_status.dart';

class AtUnshareOperation {
  /// we store the [selfKey] here, might not be needed
  AtKey selfKey;

  /// we store the [atSignsList] here
  List<String> atSignsList;

  /// stream, after each successful/unsuccessful unshare operation
  /// the [AtOperationItemStatus] is added to [atUnshareOperationStream]
  final StreamController _atUnshareOperationController =
      StreamController<AtOperationItemStatus>.broadcast();
  Stream<AtOperationItemStatus> get atUnshareOperationStream =>
      _atUnshareOperationController.stream as Stream<AtOperationItemStatus>;

  /// will contain list of all AtOperationItemStatus sent to [atUnshareOperationStream] till now
  late List<AtOperationItemStatus> allData;

  /// enum to denote current state of share
  late AtUnshareOperationStatus atUnshareOperationStatus;

  bool _stopPendingUnshares = false;

  AtUnshareOperation({
    required this.selfKey,
    required this.atSignsList,
  }) {
    allData = [];
    atUnshareOperationStatus = AtUnshareOperationStatus.INPROGRESS;
    _unshare(selfKey, atSignsList);
  }

  /// when called, any pending shares will not be processed
  void stop() {
    _stopPendingUnshares = true;
    atUnshareOperationStatus = AtUnshareOperationStatus.STOPPED;
  }

  void emitFromStream(AtOperationItemStatus _event) {
    if (!_stopPendingUnshares) {
      allData.add(_event);
      _atUnshareOperationController.sink.add(_event);
    }
  }

  void _unshare(AtKey selfKey, List<String> atSignsList) async {
    for (var atSign in atSignsList) {
      if (_stopPendingUnshares) {
        return;
      }

      var sharedAtKey = selfKey;

      sharedAtKey.sharedWith = atSign;

      try {
        /// TODO: we might need to check whether the key exists before deleting it
        var _res =
            await AtClientManager.getInstance().atClient.delete(sharedAtKey);

        _checkForUnhareOperationStatus(atSign, atSignsList);
        emitFromStream(
          AtOperationItemStatus(
            atSign: atSign,
            key: sharedAtKey.key!,
            complete: _res,
            exception: null,
          ),
        );
      } catch (e) {
        _checkForUnhareOperationStatus(atSign, atSignsList);
        emitFromStream(
          AtOperationItemStatus(
            atSign: atSign,
            key: sharedAtKey.key!,
            complete: false,
            exception: e as Exception,
          ),
        );
      }
    }
  }

  void _checkForUnhareOperationStatus(String atSign, List<String> atSignsList) {
    if ((atUnshareOperationStatus != AtUnshareOperationStatus.STOPPED) &&
        (atSignsList.indexOf(atSign) == (atSignsList.length - 1))) {
      atUnshareOperationStatus = AtUnshareOperationStatus.COMPLETE;
    }
  }
}

enum AtUnshareOperationStatus {
  INPROGRESS,
  COMPLETE,
  STOPPED,
}
