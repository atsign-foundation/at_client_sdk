 import 'dart:async';

import 'package:at_client/at_client.dart';

class AtShareOperation {
  /// we store the [data] here, might not be needed
  dynamic data;
  /// we store the [atSignsList] here
  List<String> atSignsList;

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
    required this.data,
    required this.atSignsList,
  }){
    _share(data, atSignsList);
  }

  /// when called, any pending shares will not be processed
  void stop() {
    _stopPendingShares = true;
    atShareOperationStatus = AtShareOperationStatus.STOPPED;
  }

  void emitFromStream(AtDataStatus _event) {
    if(!_stopPendingShares){
      _atShareOperationController.sink.add(_event);
    }
  }

  void _share(dynamic data, List<String> atSignsList) async {
    for(var atSign in atSignsList) {
      if(_stopPendingShares) {
        return;
      }
    
      var atKey = AtKey(); /// TODO: Create proper key
      try {
        var _res = await AtClientManager.getInstance().atClient.put(atKey, data);
        _checkForShareOperationStatus(atSign, atSignsList);
        emitFromStream(AtDataStatus(
            atSign: atSign,
            key: atKey.key!,
            complete: _res,
            exception: null,
          ),
        );
      } catch(e) {
        _checkForShareOperationStatus(atSign, atSignsList);
        emitFromStream(AtDataStatus(
            atSign: atSign,
            key: atKey.key!,
            complete: false,
            exception: e as Exception,
          ),
        );
      }
    }
  }

  void _checkForShareOperationStatus(String atSign, List<String> atSignsList) {
    if (
      (atShareOperationStatus != AtShareOperationStatus.STOPPED)
       && 
      (atSignsList.indexOf(atSign) == (atSignsList.length - 1)
    )){
      atShareOperationStatus = AtShareOperationStatus.COMPLETE;
    }
  }
}

enum AtShareOperationStatus {
  INPROGRESS,
  COMPLETE,
  STOPPED,
}