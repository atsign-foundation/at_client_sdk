import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart';

import '../util/abandonment.dart';

/// The parts of a WebSocket that is still opening that [awaitOpen] watches.
@internal
abstract interface class OpeningWebSocket {
  /// Fires once the socket is `OPEN`.
  Stream<void> get onOpen;

  /// Fires when the socket fails.
  Stream<void> get onError;

  /// Fires once, when the socket closes.
  Stream<void> get onClose;

  void close();
}

/// Completes once [socket], opened to [host] on [port], is open.
///
/// Throws [SecondaryConnectException], having closed [socket], when it fails
/// or closes first, when [timeout] elapses, the network default with none,
/// or when the work this runs inside is abandoned.
@internal
Future<void> awaitOpen(OpeningWebSocket socket, String host, String port,
    {Duration? timeout}) async {
  final bound =
      AtNetworkTimeouts.cap(timeout ?? AtNetworkTimeouts.defaultTimeout);
  final opened = Completer<void>();
  void fail(String reason) {
    if (!opened.isCompleted) opened.completeError(reason);
  }

  final subscriptions = [
    socket.onOpen.listen((_) {
      if (!opened.isCompleted) opened.complete();
    }),
    socket.onError.listen((_) => fail('WebSocket error')),
    socket.onClose.listen((_) => fail('WebSocket closed before open')),
  ];
  final timer = Timer(bound, () => fail('no answer within $bound'));
  final unregister = Abandonment.current
      ?.onAbandon(() => fail('abandoned: its owner has closed'));
  try {
    await opened.future;
  } catch (e) {
    socket.close();
    throw SecondaryConnectException(
        'unable to connect to atServer on $host:$port - $e');
  } finally {
    timer.cancel();
    unregister?.call();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
