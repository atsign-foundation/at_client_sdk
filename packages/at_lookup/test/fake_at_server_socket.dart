import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_lookup/src/connection/outbound_connection_impl.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';

/// A [Socket] the test drives by hand, over a REAL [StreamController].
///
/// at_lookup's other socket double, `createMockAtServerSocket`, stubs `listen`
/// to return a `MockStreamSubscription`. That subscription delivers nothing and
/// cannot show that pausing stops delivery, so no test in this package has ever
/// driven bytes in through a socket — every one calls
/// `OutboundMessageListener.messageHandler` directly. This class closes that
/// gap: bytes arrive the way the atServer sends them, and pause, resume, done
/// and error are real events with counters on them.
///
/// The controller is deliberately **single-subscription**. A broadcast
/// controller ignores `pause()` and buffers nothing, so a back-pressure
/// assertion written against one passes whether or not the code under test
/// pauses anything.
///
/// Anything this fake does not implement throws [UnimplementedError] naming the
/// member, so an unsupported call fails loudly instead of returning null into a
/// non-nullable type.
/// Implements [SecureSocket], not [Socket], purely so it can be injected
/// through `AtLookupImpl`'s own `secureSocketFactory` seam - which is typed
/// `Future<SecureSocket>`. Nothing calls a SecureSocket-specific member on it:
/// `createOutBoundConnection` passes the socket straight to the connection
/// factory. Implementing the narrower type forced tests to mock the connection
/// factory as well and hand it a throwaway SecureSocket that was never read
/// from - two moving parts to inject one fake.
class FakeAtServerSocket implements SecureSocket {
  late final StreamController<Uint8List> _inbound = StreamController<Uint8List>(
    onListen: () => listenCount++,
    onPause: () => pauseCount++,
    onResume: () => resumeCount++,
    onCancel: () => cancelCount++,
  );

  /// Everything the client wrote, in order, as strings.
  final List<String> written = <String>[];

  /// The subscription the last [listen] handed out.
  ///
  /// [OutboundMessageListener.listen] discards its subscription, so a test that
  /// wants to pause delivery has no other handle on it.
  StreamSubscription<Uint8List>? subscription;

  int listenCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int cancelCount = 0;
  int flushCount = 0;
  bool destroyed = false;

  /// True while the subscription the listener holds is paused.
  bool get isPaused => subscription?.isPaused ?? false;

  /// Push bytes at the client as the atServer would, then let the event loop
  /// deliver them. Await this and the listener has seen them - or has provably
  /// not, when the subscription is paused.
  Future<void> serverSends(String data) async {
    _inbound.add(Uint8List.fromList(utf8.encode(data)));
    await settle();
  }

  /// The far end went away. Drives the listener's `onDone`.
  Future<void> serverCloses() async {
    await _inbound.close();
    await settle();
  }

  /// The far end faulted. Drives the listener's `onError`.
  Future<void> serverErrors(Object error) async {
    _inbound.addError(error);
    await settle();
  }

  /// Yield long enough for stream delivery and the async `messageHandler` it
  /// calls. `Duration.zero` alone drains microtasks but not the timer queue
  /// that an awaited handler can land on.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration.zero);
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return subscription = _inbound.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');

  @override
  void add(List<int> data) => written.add(utf8.decode(data));

  @override
  Future<void> flush() async => flushCount++;

  @override
  void destroy() {
    destroyed = true;
    if (!_inbound.isClosed) _inbound.close();
  }

  @override
  Future<void> close() async => destroy();

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  InternetAddress get remoteAddress => InternetAddress('127.0.0.66');

  @override
  int get remotePort => 6464;

  @override
  InternetAddress get address => InternetAddress('127.0.0.1');

  @override
  int get port => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeAtServerSocket does not implement '
      '${invocation.memberName}. Add it here rather than working around it.');
}

/// A listener wired to a real [OutboundConnectionImpl] over a
/// [FakeAtServerSocket], already listening.
///
/// The connection is the production class, not a double, so the harness
/// exercises the real `close()`/`write()` path down to the socket.
class FakeAtServerRig {
  final FakeAtServerSocket socket;
  final OutboundConnectionImpl connection;
  final OutboundMessageListener listener;

  FakeAtServerRig._(this.socket, this.connection, this.listener);

  factory FakeAtServerRig({int bufferCapacity = 10240000}) {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);
    final listener =
        OutboundMessageListener(connection, bufferCapacity: bufferCapacity);
    listener.listen();
    return FakeAtServerRig._(socket, connection, listener);
  }
}
