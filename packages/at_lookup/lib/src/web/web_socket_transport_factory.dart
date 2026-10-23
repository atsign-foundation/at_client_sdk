import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:web/web.dart';

import '../transport/at_transport.dart';
import 'web_socket_transport.dart';

/// Opens [WebSocketTransport]s to `scheme://host:port` + [path].
///
/// The atServer upgrades [path] on its TLS port, so [scheme] is `wss` outside
/// tests. [flushTimeout] bounds each `flush` of a transport it opens.
class WebSocketTransportFactory implements AtTransportFactory {
  final String path;
  final String scheme;
  final Duration flushTimeout;

  const WebSocketTransportFactory(
      {this.path = '/ws',
      this.scheme = 'wss',
      this.flushTimeout = const Duration(seconds: 30)});

  /// An `error` or `close` before `open`, and a [timeout] elapsing, surface
  /// as [SecondaryConnectException]; the cause is kept in the message.
  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final url = '$scheme://$host:$port$path';
    final socket = WebSocket(url)..binaryType = 'arraybuffer';
    final opened = Completer<void>();
    void fail(String reason) {
      if (!opened.isCompleted) opened.completeError(reason);
    }

    final subscriptions = [
      socket.onOpen.listen((_) => opened.complete()),
      socket.onError.listen((_) => fail('WebSocket error')),
      socket.onClose.listen((_) => fail('WebSocket closed before open')),
    ];
    try {
      await (timeout == null ? opened.future : opened.future.timeout(timeout));
      return WebSocketTransport(_BrowserWebSocketPort(socket), url,
          flushTimeout: flushTimeout);
    } catch (e) {
      socket.close();
      throw SecondaryConnectException(
          'unable to connect to atServer on $host:$port - $e');
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }
}

class _BrowserWebSocketPort implements WebSocketPort {
  final WebSocket _socket;

  _BrowserWebSocketPort(this._socket);

  @override
  bool get isOpen => _socket.readyState == WebSocket.OPEN;

  @override
  int get bufferedAmount => _socket.bufferedAmount;

  @override
  void send(Uint8List bytes) => _socket.send(bytes.toJS);

  @override
  Stream<Object?> get onMessage =>
      _socket.onMessage.map((event) => _dartData(event.data));

  @override
  Stream<void> get onClose => _socket.onClose;

  @override
  void close() => _socket.close();

  static Object? _dartData(JSAny? data) {
    if (data == null) return null;
    if (data.typeofEquals('string')) return (data as JSString).toDart;
    if (data.instanceOfString('ArrayBuffer')) {
      return (data as JSArrayBuffer).toDart;
    }
    return data;
  }
}
