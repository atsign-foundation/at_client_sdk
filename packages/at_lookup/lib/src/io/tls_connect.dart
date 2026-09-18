import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../util/abandonment.dart';

export '../util/abandonment.dart';

/// Opens a TLS connection to [host]:[port], bounded by [timeout] from the TCP
/// connect to the end of the handshake.
///
/// Built on [RawSocket] rather than [SecureSocket.connect], whose timeout
/// bounds only the TCP connect: a peer that accepts and never answers the
/// handshake leaves that connect pending for ever, and nothing reachable
/// through its API closes the socket, so it also keeps the process alive.
/// Here the raw socket closes on the timeout, or when the [Abandonment] this
/// runs inside is abandoned, and the returned future fails with a
/// [SocketException].
Future<SecureSocket> connectTls(
  String host,
  int port, {
  required SecurityContext context,
  required Duration timeout,
  void Function(String line)? keyLog,
}) async {
  final ended = Completer<Never>();
  ended.future.ignore();
  Object? endedBy;
  ConnectionTask<RawSocket>? task;
  RawSocket? raw;

  void end(Object reason) {
    if (endedBy != null) return;
    endedBy = reason;
    task?.cancel();
    raw?.close();
    ended.completeError(reason);
  }

  /// [work]'s value, unless the connect ends first; a value that arrives
  /// after that is handed to [dispose].
  Future<T> unlessEnded<T>(Future<T> work, void Function(T) dispose) async {
    unawaited(work.then((value) {
      if (endedBy != null) dispose(value);
    }, onError: (_) {}));
    final value = await Future.any([work, ended.future]);
    if (endedBy != null) throw endedBy!;
    return value;
  }

  final timer = Timer(
      timeout,
      () => end(SocketException(
          'Connection timed out: TLS connect to $host:$port did not complete '
          'within $timeout')));
  final unregister = Abandonment.current?.onAbandon(() => end(SocketException(
      'TLS connect to $host:$port abandoned: its owner has closed')));
  try {
    final connecting =
        await unlessEnded(RawSocket.startConnect(host, port), (task) {
      task.socket.ignore();
      task.cancel();
    });
    task = connecting;
    final connected =
        await unlessEnded(connecting.socket, (socket) => socket.close());
    raw = connected;
    connected.setOption(SocketOption.tcpNoDelay, true);
    final secure = await unlessEnded(
        RawSecureSocket.secure(connected,
            host: host, context: context, keyLog: keyLog),
        (socket) => socket.close());
    return _TlsSocket(secure);
  } finally {
    timer.cancel();
    unregister?.call();
  }
}

/// A [SecureSocket] over a [RawSecureSocket], for the members at_lookup's
/// connections use and the rest of the interface.
class _TlsSocket extends Stream<Uint8List> implements SecureSocket {
  _TlsSocket(this._raw) {
    // NOTE: reads wait for a listener that is not paused, which is how
    // back-pressure reaches the peer; writes must not, so only read events
    // are gated.
    _raw
      ..readEventsEnabled = false
      ..writeEventsEnabled = false
      ..listen(_onEvent, onError: _onError, onDone: _onRawDone);
  }

  final RawSecureSocket _raw;
  late final StreamController<Uint8List> _incoming = StreamController(
    onListen: () => _raw.readEventsEnabled = true,
    onPause: () => _raw.readEventsEnabled = false,
    onResume: () => _raw.readEventsEnabled = true,
    onCancel: () => _raw.readEventsEnabled = false,
  );
  final Queue<Uint8List> _outgoing = Queue();
  int _outgoingOffset = 0;
  Completer<void>? _drained;
  final Completer<void> _done = Completer<void>();
  bool _destroyed = false;

  @override
  Encoding encoding = utf8;

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _incoming.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  void _onEvent(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        final data = _raw.read();
        if (data != null) _incoming.add(data);
      case RawSocketEvent.write:
        _drain();
      case RawSocketEvent.readClosed:
        _closeIncoming();
      case RawSocketEvent.closed:
        _onRawDone();
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_incoming.isClosed) _incoming.addError(error, stackTrace);
    _failWrites(error);
  }

  void _onRawDone() {
    _closeIncoming();
    _failWrites(const SocketException.closed());
    if (!_done.isCompleted) _done.complete();
  }

  void _closeIncoming() {
    if (!_incoming.isClosed) _incoming.close();
  }

  void _failWrites(Object error) {
    _outgoing.clear();
    _outgoingOffset = 0;
    final drained = _drained;
    _drained = null;
    drained?.completeError(error);
  }

  void _drain() {
    while (_outgoing.isNotEmpty) {
      final chunk = _outgoing.first;
      _outgoingOffset += _raw.write(chunk, _outgoingOffset);
      if (_outgoingOffset < chunk.length) {
        _raw.writeEventsEnabled = true;
        return;
      }
      _outgoing.removeFirst();
      _outgoingOffset = 0;
    }
    final drained = _drained;
    _drained = null;
    drained?.complete();
  }

  @override
  void add(List<int> data) {
    if (_destroyed) throw const SocketException.closed();
    if (data.isEmpty) return;
    _outgoing.add(data is Uint8List ? data : Uint8List.fromList(data));
    _drain();
  }

  @override
  void write(Object? object) => add(encoding.encode('$object'));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    destroy();
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> flush() {
    if (_outgoing.isEmpty) return Future.value();
    return (_drained ??= Completer<void>()).future;
  }

  @override
  Future<void> close() async {
    try {
      await flush();
    } finally {
      destroy();
    }
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _raw.close();
    _onRawDone();
  }

  @override
  Future<void> get done => _done.future;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _raw.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _raw.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _raw.setRawOption(option);

  @override
  InternetAddress get address => _raw.address;

  @override
  int get port => _raw.port;

  @override
  InternetAddress get remoteAddress => _raw.remoteAddress;

  @override
  int get remotePort => _raw.remotePort;

  @override
  X509Certificate? get peerCertificate => _raw.peerCertificate;

  @override
  String? get selectedProtocol => _raw.selectedProtocol;

  @override
  void renegotiate(
          {bool useSessionCache = true,
          bool requestClientCertificate = false,
          bool requireClientCertificate = false}) =>
      throw UnsupportedError('renegotiate is not supported');
}
