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

  /// A URL the WebSocket constructor refuses, an `error` or `close` before
  /// `open`, an attempt not opening within five seconds, [timeout] elapsing
  /// (the ladder's own 20-second bound with none), and a close of the lookup
  /// it opens for, surface as [SecondaryConnectException]; the cause is kept
  /// in the message.
  ///
  /// For `wss` it first sends a pre-flight request to the https origin and
  /// waits for it at most min(2 s, half of [timeout]), so a TLS listener that
  /// asks for a client certificate has answered before the first handshake.
  ///
  /// A failed attempt is retried on a fresh socket, after a one-second pause
  /// and then a two-second one: three attempts in all, unless [timeout] runs
  /// out first or the lookup is closed.
  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final url = '$scheme://$host:$port$path';
    final socket = await openWithRetry(() {
      final WebSocket webSocket;
      try {
        webSocket = WebSocket(url);
      } catch (e) {
        throw SecondaryConnectException(
            'unable to connect to atServer on $host:$port - $e');
      }
      return _BrowserWebSocketPort(webSocket..binaryType = 'arraybuffer');
    }, host, port,
        timeout: timeout,
        prepare: preflightStep(scheme, host, port, _preflight));
    return WebSocketTransport(socket, url, flushTimeout: flushTimeout);
  }
}

/// Wakes the TLS listener at [origin] before any WebSocket is opened to it.
///
/// An atServer's TLS listener requests a client certificate. Chromium cancels
/// a cold WebSocket handshake to such a listener, but opens it after any HTTPS
/// request to the same origin has been answered with "no certificate". The
/// request is `no-cors` (opaque response; Chromium would also reject a
/// `manual` redirect mode with it). It carries no `signal`, so it is never
/// aborted: only its reaching the listener matters, and the ladder ignores
/// its result and its errors.
Future<void> _preflight(String origin) async {
  await window
      .fetch(
          origin.toJS,
          RequestInit(
              method: 'GET',
              mode: 'no-cors',
              credentials: 'include',
              cache: 'no-store'))
      .toDart;
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
