/// A bidirectional byte channel to an atServer, opened by an
/// [AtTransportFactory].
///
/// This is everything `at_lookup` needs from a connection, and deliberately no
/// more: it is what remains after `dart:io`'s `Socket` comes off the
/// `AtConnection` interface. A `SecureSocket` satisfies it as it stands; a
/// `WebSocket` can be wrapped to.
///
/// There is no `connect()` here. A transport only exists once
/// [AtTransportFactory.connect] has returned one, so no member has to guard an
/// unconnected state.
abstract interface class AtTransport {
  /// The bytes arriving from the far end. Single-subscription.
  ///
  /// An implementation MUST return the underlying stream and MUST NOT wrap it
  /// in a `StreamController`. Pausing this subscription is how `at_lookup`
  /// applies back-pressure to the far end; a controller answers the pause out
  /// of a local buffer instead, and the far end keeps sending.
  /// `Socket implements Stream<Uint8List>`, so the socket transport returns
  /// the socket itself and pause and resume survive by construction.
  ///
  /// `List<int>` rather than `Uint8List` because that is what
  /// `OutboundMessageListener` consumes, and it is what lets a `WebSocket`
  /// implement this.
  Stream<List<int>> get inbound;

  /// Queues [bytes] for delivery to the far end.
  void add(List<int> bytes);

  /// Completes once everything passed to [add] has left this process.
  Future<void> flush();

  /// Renders the channel unusable and discards whatever is still queued.
  ///
  /// Synchronous, because there is no outcome to wait for: it yields no result
  /// and no failure a caller could branch on. A graceful shutdown is
  /// `await flush(); destroy();`, spelled at the call site. Teardown that does
  /// have something to await belongs on `AtConnection.close()`; an awaitable
  /// teardown here would let a WebSocket close handshake block the reconnect
  /// loop on a peer that never answers.
  void destroy();

  /// Identifies the far end well enough for one log line.
  String get description;
}

/// Opens [AtTransport]s.
///
/// Naming an implementation of this is what selects a transport — and, because
/// the socket implementation is exported from
/// `package:at_lookup/at_lookup_io.dart` rather than from the default barrel,
/// it is also what pulls in the library that carries the native imports.
abstract interface class AtTransportFactory {
  /// Opens a channel to [host] on [port], giving up after [timeout].
  ///
  /// Throws `SecondaryConnectException` if the far end cannot be reached.
  Future<AtTransport> connect(String host, String port, {Duration? timeout});
}
