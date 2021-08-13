import 'dart:async';
import 'package:internet_connection_checker/internet_connection_checker.dart';

/// Listener class that returns a Stream<True> if internet connection is on in the running device, Stream<False> if internet gets disconnected.
/// Sample usage
/// ```
/// ConnectivityListener().subscribe().listen((isConnected) {
///   if (isConnected) {
///     print('connection available');
///    } else {
///     print('connection lost');
///   }
/// });
/// ```
class ConnectivityListener {
  var _listener;

  /// Listen to [InternetConnectionChecker.onStatusChange] and returns Stream<True> whenever
  /// internet connection is online. Returns Stream<False> if internet connection is lost.
  Stream<bool> subscribe() {
    final _controller = StreamController<bool>();
    _listener = InternetConnectionChecker().onStatusChange.listen((status) {
      switch (status) {
        case InternetConnectionStatus.connected:
          _controller.add(true);
          break;
        case InternetConnectionStatus.disconnected:
          _controller.add(false);
          break;
      }
    });
    return _controller.stream;
  }

  /// Cancels the active subscription to [InternetConnectionChecker]
  void unSubscribe() {
    if (_listener != null) {
      _listener.cancel();
    }
  }
}
