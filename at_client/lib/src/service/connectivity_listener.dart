import 'dart:async';

import 'package:data_connection_checker/data_connection_checker.dart';

class ConnectivityListener {
  var _listener;
  Stream<bool> subscribe() {
    final _controller = StreamController<bool>();
    _listener = DataConnectionChecker().onStatusChange.listen((status) {
      switch (status) {
        case DataConnectionStatus.connected:
          _controller.add(true);
          break;
        case DataConnectionStatus.disconnected:
          _controller.add(false);
          break;
      }
    });
    return _controller.stream;
  }

  void unSubscribe() {
    if (_listener != null) {
      _listener.cancel();
    }
  }
}
