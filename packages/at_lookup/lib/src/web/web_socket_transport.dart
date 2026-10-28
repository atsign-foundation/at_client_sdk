import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

import '../transport/at_transport.dart';
import 'ws_frame.dart';

/// The parts of a WebSocket that [WebSocketTransport] drives.
@internal
abstract interface class WebSocketPort {
  /// Whether the socket's `readyState` is `OPEN`.
  bool get isOpen;

  /// Bytes passed to [send] that have not yet left the process.
  int get bufferedAmount;

  void send(Uint8List bytes);

  /// Each received frame's payload: a `String` or a `ByteBuffer`.
  Stream<Object?> get onMessage;

  /// Fires once, when the socket closes.
  Stream<void> get onClose;

  void close();
}

/// A WebSocket as an [AtTransport].
///
/// Frames go out binary. Frames come in as text or binary, and both reach
/// [inbound] as bytes.
class WebSocketTransport implements AtTransport {
  final WebSocketPort _port;
  final int _maxInboundBytes;
  final Duration _flushTimeout;
  final int _highWaterMark;
  final Duration _flushPollInterval;
  final AtSignLogger _logger;

  late final StreamController<List<int>> _inbound = StreamController<List<int>>(
      sync: true, onListen: _scheduleDrain, onResume: _scheduleDrain);
  final Queue<List<int>> _held = Queue<List<int>>();
  int _heldBytes = 0;
  bool _closed = false;

  @override
  final String description;

  @internal
  WebSocketTransport(
    this._port,
    this.description, {
    int maxInboundBytes = 10240000,
    Duration flushTimeout = const Duration(seconds: 30),
    int highWaterMark = 65536,
    Duration flushPollInterval = const Duration(milliseconds: 10),
    AtSignLogger? logger,
  })  : _maxInboundBytes = maxInboundBytes,
        _flushTimeout = flushTimeout,
        _highWaterMark = highWaterMark,
        _flushPollInterval = flushPollInterval,
        _logger = logger ?? AtSignLogger('WebSocketTransport') {
    _port.onMessage.listen(_receive);
    _port.onClose.listen((_) => _peerClosed());
  }

  /// Single-subscription. A WebSocket cannot be paused, so while this
  /// subscription is paused or not yet listened to, frames are held here, up
  /// to `maxInboundBytes`. Past that the socket is closed and this stream
  /// ends with an [AtIOException].
  @override
  Stream<List<int>> get inbound => _inbound.stream;

  /// Throws [AtIOException], sending nothing, once the socket is not `OPEN`.
  @override
  void add(List<int> bytes) {
    if (_closed || !_port.isOpen) {
      throw AtIOException('WebSocket to $description is closed');
    }
    _port.send(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }

  /// Completes once the socket's `bufferedAmount` is at most `highWaterMark`,
  /// at once when it already is, polling for it otherwise.
  ///
  /// Throws [AtTimeoutException] if it is not within `flushTimeout`, and
  /// [AtIOException] if the socket closes first.
  @override
  Future<void> flush() async {
    final elapsed = Stopwatch()..start();
    while (_port.bufferedAmount > _highWaterMark) {
      if (_closed || !_port.isOpen) {
        throw AtIOException(
            'WebSocket to $description closed with ${_port.bufferedAmount} '
            'bytes unsent');
      }
      if (elapsed.elapsed > _flushTimeout) {
        throw AtTimeoutException(
            'WebSocket to $description still had ${_port.bufferedAmount} '
            'bytes unsent after $_flushTimeout');
      }
      await Future<void>.delayed(_flushPollInterval);
    }
  }

  @override
  bool get isOpen => !_closed && _port.isOpen;

  /// Closes the socket and [inbound]. Calling it again does nothing.
  @override
  void destroy() {
    if (_closed) return;
    _closed = true;
    _port.close();
    _held.clear();
    _inbound.close();
  }

  void _receive(Object? data) {
    if (_closed) return;
    final bytes = frameBytes(data);
    if (_held.isEmpty && _canDeliver) {
      _inbound.add(bytes);
      return;
    }
    _held.add(bytes);
    _heldBytes += bytes.length;
    if (_heldBytes > _maxInboundBytes) _overflow();
  }

  bool get _canDeliver => _inbound.hasListener && !_inbound.isPaused;

  void _scheduleDrain() => scheduleMicrotask(_drain);

  void _drain() {
    while (_held.isNotEmpty && _canDeliver) {
      final bytes = _held.removeFirst();
      _heldBytes -= bytes.length;
      _inbound.add(bytes);
    }
  }

  void _overflow() {
    _logger.warning('$description: closing, $_heldBytes inbound bytes held '
        'unread, over the $_maxInboundBytes-byte bound');
    _closed = true;
    _port.close();
    _held.clear();
    _inbound
      ..addError(AtIOException('WebSocket to $description closed: over '
          '$_maxInboundBytes inbound bytes held unread'))
      ..close();
  }

  void _peerClosed() {
    if (_closed) return;
    _closed = true;
    _held.forEach(_inbound.add);
    _held.clear();
    _inbound.close();
  }
}
