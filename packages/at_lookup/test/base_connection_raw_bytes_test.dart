import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// A connection's raw byte path, `inbound` and `add`.
void main() {
  test('add writes raw bytes to the far end', () async {
    final transport = _ByteTransport();
    final connection = OutboundConnectionImpl(transport);

    connection.add(utf8.encode('raw bytes'));

    expect(transport.written, ['raw bytes']);
  });

  test('inbound carries the bytes the far end sends', () async {
    final transport = _ByteTransport();
    final connection = OutboundConnectionImpl(transport);
    final received = <String>[];
    connection.inbound.listen((bytes) => received.add(utf8.decode(bytes)));

    await transport.serverSends('data:ok\n');

    expect(received, ['data:ok\n']);
  });

  test('inbound takes a List<int> transformer, such as utf8.decoder', () async {
    final transport = _ByteTransport();
    final connection = OutboundConnectionImpl(transport);
    final received = <String>[];
    connection.inbound.transform(utf8.decoder).listen(received.add);

    await transport.serverSends('data:ok\n');

    expect(received, ['data:ok\n']);
  });

  test('pausing a subscription to inbound pauses the transport', () async {
    final transport = _ByteTransport();
    final connection = OutboundConnectionImpl(transport);
    final received = <String>[];
    final subscription =
        connection.inbound.listen((bytes) => received.add(utf8.decode(bytes)));

    subscription.pause();
    await transport.serverSends('data:ok\n');
    expect(transport.isPaused, isTrue,
        reason: 'pausing a subscription to inbound pauses the transport');
    expect(received, isEmpty,
        reason: 'nothing is delivered while the subscription is paused');

    subscription.resume();
    await transport.settle();
    expect(received, ['data:ok\n'],
        reason: 'resuming delivers what arrived while paused');
  });
}

/// A transport whose inbound is a `Stream<Uint8List>`, as a socket's is.
class _ByteTransport implements AtTransport {
  final _inbound = StreamController<Uint8List>();

  /// Everything written, decoded.
  final List<String> written = [];

  bool get isPaused => _inbound.isPaused;

  Future<void> serverSends(String data) async {
    _inbound.add(Uint8List.fromList(utf8.encode(data)));
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration.zero);
    }
  }

  @override
  String get description => '127.0.0.66:6464';

  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) => written.add(utf8.decode(bytes));

  @override
  Future<void> flush() async {}

  @override
  bool get isOpen => !_inbound.isClosed;

  @override
  void destroy() {
    if (!_inbound.isClosed) _inbound.close();
  }
}
