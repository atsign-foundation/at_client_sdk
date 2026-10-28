import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:web/web.dart';

import '../transport/at_transport.dart';
import 'web_socket_open.dart';
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

  /// An `error` or `close` before `open`, [timeout] elapsing (the network
  /// default with none), and a close of the lookup it opens for, surface as
  /// [SecondaryConnectException]; the cause is kept in the message.
  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final url = '$scheme://$host:$port$path';
    final socket =
        _BrowserWebSocketPort(WebSocket(url)..binaryType = 'arraybuffer');
    await awaitOpen(socket, host, port, timeout: timeout);
    return WebSocketTransport(socket, url, flushTimeout: flushTimeout);
  }
}

class _BrowserWebSocketPort implements WebSocketPort, OpeningWebSocket {
  final WebSocket _socket;

  _BrowserWebSocketPort(this._socket);

  @override
  Stream<void> get onOpen => _socket.onOpen;

  @override
  Stream<void> get onError => _socket.onError;

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
