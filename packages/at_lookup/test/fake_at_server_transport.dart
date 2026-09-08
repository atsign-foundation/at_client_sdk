import 'dart:async';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';

/// An [AtTransport] the test drives by hand, over a REAL [StreamController].
///
/// This replaces the mocktail `MockSecureSocket`, which stubbed `listen` to
/// return a subscription that delivered nothing and could not record a pause.
/// A double that cannot show a pause makes a back-pressure assertion pass
/// whether or not the code under test pauses anything.
///
/// The controller is deliberately **single-subscription**. A broadcast
/// controller ignores `pause()` and buffers nothing, so the same assertion
/// passes vacuously there too.
///
/// Nothing here names a socket, which is the point: what it exercises is the
/// [AtTransport] contract, so a WebSocket transport would satisfy the same
/// tests.
class FakeAtServerTransport implements AtTransport {
  late final StreamController<List<int>> _inbound = StreamController<List<int>>(
    onListen: () => listenCount++,
    onPause: () => pauseCount++,
    onResume: () => resumeCount++,
    onCancel: () => cancelCount++,
  );

  @override
  final String description;

  FakeAtServerTransport({this.description = '127.0.0.66:6464'});

  final List<String> written = <String>[];
  bool failWrites = false;

  int listenCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int cancelCount = 0;
  int flushCount = 0;
  bool destroyed = false;

  Future<void> serverSends(String data) async {
    _inbound.add(utf8.encode(data));
    await settle();
  }

  Future<void> serverCloses() async {
    await _inbound.close();
    await settle();
  }

  Future<void> serverErrors(Object error) async {
    _inbound.addError(error);
    await settle();
  }

  /// `Duration.zero` alone drains microtasks but not the timer queue
  /// that an awaited handler can land on.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration.zero);
    }
  }

  /// The controller's own stream, never a re-broadcast of it — the invariant
  /// [AtTransport] states, held here so a test asserting on [pauseCount] is
  /// asserting on something real.
  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) {
    if (failWrites) throw AtIOException('write rejected');
    written.add(utf8.decode(bytes));
  }

  @override
  Future<void> flush() async => flushCount++;

  @override
  void destroy() {
    destroyed = true;
    if (!_inbound.isClosed) _inbound.close();
  }
}

/// Hands out [FakeAtServerTransport]s and keeps every one it made.
///
/// [created] is how a test reaches the transport a connection was built over
/// now that `AtConnection` no longer hands one back. It replaces the global
/// `mockSocketNumber` counter, which numbered instances so that a test could
/// tell the first connection's socket from the second's — an ordering the
/// list expresses directly.
class FakeAtServerTransportFactory implements AtTransportFactory {
  final List<FakeAtServerTransport> created = <FakeAtServerTransport>[];

  /// Thrown from [connect] instead of connecting, when set.
  Object? connectFailure;

  /// Applied to each transport before it is handed out.
  void Function(FakeAtServerTransport transport)? onCreate;

  FakeAtServerTransport get last => created.last;

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    if (connectFailure case final failure?) throw failure;
    final transport = FakeAtServerTransport(description: '$host:$port');
    onCreate?.call(transport);
    created.add(transport);
    return transport;
  }
}

/// A listener wired to a real [OutboundConnectionImpl] over a
/// [FakeAtServerTransport], already listening.
class FakeAtServerRig {
  final FakeAtServerTransport transport;
  final OutboundConnectionImpl connection;
  final OutboundMessageListener listener;

  FakeAtServerRig._(this.transport, this.connection, this.listener);

  factory FakeAtServerRig({int bufferCapacity = 10240000}) {
    final transport = FakeAtServerTransport();
    final connection = OutboundConnectionImpl(transport);
    final listener =
        OutboundMessageListener(connection, bufferCapacity: bufferCapacity);
    listener.listen();
    return FakeAtServerRig._(transport, connection, listener);
  }
}
