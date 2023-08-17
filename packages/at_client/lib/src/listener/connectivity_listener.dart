import 'dart:async';

import 'package:internet_connection_checker/internet_connection_checker.dart';

/// @Deprecated Will be removed in a future release. Please use a connectivity checker of your own choice in your application code
///
/// Listener class that returns a Stream<True> if internet connection is on in the running device, Stream<False> if internet gets disconnected.
/// Sample usage
/// ```
/// ConnectivityListener({hostname:'google.com', port:80}).subscribe().listen((isConnected) {
///   if (isConnected) {
///     print('connection available');
///    } else {
///     print('connection lost');
///   }
/// });
/// ```
@Deprecated('Will be removed in a future release.'
    ' Please use a connectivity checker of your own choice'
    ' in your application code')
class ConnectivityListener {
  late final String? hostname;
  late final int? port;
  late final Duration checkInterval;
  late final StreamSubscription _listener;

  ConnectivityListener(
      {this.hostname,
      this.port,
      this.checkInterval = const Duration(seconds: 10)}) {
    if (hostname != null && port == null) {
      throw ArgumentError('port may not be null if hostname is provided');
    }
    if (hostname == null && port != null) {
      throw ArgumentError('hostname may not be null if port is provided');
    }
  }

  /// Listen to [InternetConnectionChecker.onStatusChange] and returns Stream<True> whenever
  /// internet connection is online. Returns Stream<False> if internet connection is lost.
  Stream<bool> subscribe() {
    late final InternetConnectionChecker icc;
    if (hostname != null && port != null) {
      icc = InternetConnectionChecker.createInstance(
          checkInterval: checkInterval,
          addresses: [AddressCheckOptions(hostname: hostname!, port: port!)]);
    } else {
      icc = InternetConnectionChecker.createInstance(
          checkInterval: checkInterval);
    }
    final sc = StreamController<bool>();
    _listener = icc.onStatusChange.listen((status) {
      switch (status) {
        case InternetConnectionStatus.connected:
          sc.add(true);
          break;
        case InternetConnectionStatus.disconnected:
          sc.add(false);
          break;
      }
    });
    return sc.stream;
  }

  /// Cancels the active subscription to [InternetConnectionChecker]
  void unSubscribe() {
    _listener.cancel();
  }
}
