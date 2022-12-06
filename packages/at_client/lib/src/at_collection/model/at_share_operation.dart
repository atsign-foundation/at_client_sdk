import 'dart:async';

import 'package:at_client/at_client.dart';

class AtShareOperation {
  /// we store the [data] here, might not be needed
  String jsonEncodedData;

  /// we store the [atSignsList] here
  List<String> atSignsList;

  AtKey selfAtKey;

  /// stream, after each successful/unsuccessful share operation
  /// the [AtDataStatus] is added to [atShareOperationStream]
  final StreamController _atShareOperationController =
      StreamController<AtDataStatus>.broadcast();
  Stream<AtDataStatus> get atShareOperationStream =>
      _atShareOperationController.stream as Stream<AtDataStatus>;

  /// will contain list of all AtDataStatus sent to [atShareOperationStream] till now
  late List<AtDataStatus> allData;

  /// enum to denote current state of share
  late AtShareOperationStatus atShareOperationStatus;

  bool _stopPendingShares = false;

  AtShareOperation({
    required this.jsonEncodedData,
    required this.atSignsList,
    required this.selfAtKey,
  }) {
    allData = [];
    atShareOperationStatus = AtShareOperationStatus.INPROGRESS;
    _share();
  }

  /// when called, any pending shares will not be processed
  void stop() {
    _stopPendingShares = true;
    atShareOperationStatus = AtShareOperationStatus.STOPPED;
  }

  void emitFromStream(AtDataStatus _event) {
    if (!_stopPendingShares) {
      allData.add(_event);
      _atShareOperationController.sink.add(_event);
    }
  }

  void _share() async {
    for (var atSign in atSignsList) {
      if (_stopPendingShares) {
        return;
      }

      var sharedAtKey = selfAtKey;
      sharedAtKey.sharedWith = atSign;

      try {
        var _res = await AtClientManager.getInstance()
            .atClient
            .put(sharedAtKey, jsonEncodedData);
        _checkForShareOperationStatus(atSign, atSignsList);
        emitFromStream(
          AtDataStatus(
            atSign: atSign,
            key: sharedAtKey.key!,
            complete: _res,
            exception: null,
          ),
        );
      } catch (e) {
        _checkForShareOperationStatus(atSign, atSignsList);
        emitFromStream(
          AtDataStatus(
            atSign: atSign,
            key: sharedAtKey.key!,
            complete: false,
            exception: e as Exception,
          ),
        );
      }
    }
  }

  void _checkForShareOperationStatus(String atSign, List<String> atSignsList) {
    if ((atShareOperationStatus != AtShareOperationStatus.STOPPED) &&
        (atSignsList.indexOf(atSign) == (atSignsList.length - 1))) {
      atShareOperationStatus = AtShareOperationStatus.COMPLETE;
    }
  }
}

enum AtShareOperationStatus {
  INPROGRESS,
  COMPLETE,
  STOPPED,
}
