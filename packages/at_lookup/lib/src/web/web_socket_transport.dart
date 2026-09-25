import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:web/web.dart';

import '../transport/at_transport.dart';
import 'ws_frame.dart';

/// A browser [WebSocket] as an [AtTransport].
///
/// Frames go out binary. Frames come in as text or binary, and both reach
/// [inbound] as bytes.
class WebSocketTransport implements AtTransport {
  final WebSocket _socket;
  final StreamController<List<int>> _inbound = StreamController<List<int>>();
  bool _destroyed = false;

  @override
  final String description;

  WebSocketTransport._(this._socket, this.description) {
    _socket.onMessage.listen((event) {
      if (_destroyed) return;
      try {
        _inbound.add(frameBytes(_dartData(event.data)));
      } catch (e, st) {
        _inbound.addError(e, st);
      }
    });
    _socket.onClose.listen((_) => _closeInbound());
  }

  /// A single-subscription controller fed by the socket's `message` events,
  /// closed on its `close` event.
  ///
  /// A browser WebSocket has no pause or back-pressure, so this controller
  /// buffers nothing that could be pushed back.
  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) => _socket
      .send((bytes is Uint8List ? bytes : Uint8List.fromList(bytes)).toJS);

  /// Completes at once: `send` hands each frame to the browser whole.
  @override
  Future<void> flush() async {}

  /// Closes the socket and [inbound]. Calling it again does nothing.
  @override
  void destroy() {
    if (_destroyed) return;
    _socket.close();
    _closeInbound();
  }

  void _closeInbound() {
    _destroyed = true;
    if (!_inbound.isClosed) _inbound.close();
  }

  static Object? _dartData(JSAny? data) {
    if (data == null) return null;
    if (data.typeofEquals('string')) return (data as JSString).toDart;
    if (data.instanceOfString('ArrayBuffer')) {
      return (data as JSArrayBuffer).toDart;
    }
    return data;
  }
}

/// Opens [WebSocketTransport]s to `scheme://host:port` + [path].
///
/// The atServer upgrades [path] on its TLS port, so [scheme] is `wss` outside
/// tests.
class WebSocketTransportFactory implements AtTransportFactory {
  final String path;
  final String scheme;

  const WebSocketTransportFactory({this.path = '/ws', this.scheme = 'wss'});

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
      return WebSocketTransport._(socket, url);
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
