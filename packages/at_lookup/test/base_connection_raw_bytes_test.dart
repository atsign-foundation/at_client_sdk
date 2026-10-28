import 'dart:convert';

import 'package:at_lookup/src/connection/outbound_connection_impl.dart';
import 'package:test/test.dart';

import 'fake_at_server_socket.dart';

/// A connection's raw byte path, `inbound` and `add`, which replace
/// `getSocket()`.
void main() {
  test('add writes raw bytes to the far end', () async {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);

    connection.add(utf8.encode('raw bytes'));

    expect(socket.written, ['raw bytes']);
  });

  test('inbound carries the bytes the far end sends', () async {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);
    final received = <String>[];
    connection.inbound.listen((bytes) => received.add(utf8.decode(bytes)));

    await socket.serverSends('data:ok\n');

    expect(received, ['data:ok\n']);
  });

  test('inbound takes a List<int> transformer, such as utf8.decoder', () async {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);
    final received = <String>[];
    connection.inbound.transform(utf8.decoder).listen(received.add);

    await socket.serverSends('data:ok\n');

    expect(received, ['data:ok\n']);
  });

  test('pausing a subscription to inbound pauses the socket', () async {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);
    final received = <String>[];
    final subscription =
        connection.inbound.listen((bytes) => received.add(utf8.decode(bytes)));

    subscription.pause();
    await socket.serverSends('data:ok\n');
    expect(socket.isPaused, isTrue);
    expect(received, isEmpty);

    subscription.resume();
    await socket.settle();
    expect(received, ['data:ok\n']);
  });
}
