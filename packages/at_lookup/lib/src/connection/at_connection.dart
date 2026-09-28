/// A live conversation with an atServer, over whatever [AtTransport] opened it.
///
/// Nothing here names a socket. Bytes go out through [write] or [add] and
/// arrive on [inbound]; what carries them is the transport's business.
abstract class AtConnection {
  /// Write [data] to the far end and wait for it to leave.
  ///
  /// Was declared `void` while every implementation returned a `Future` - a
  /// caller reading the interface had no reason to await, and an unawaited
  /// failure surfaces as an unhandled async error rather than as the
  /// [ConnectionInvalidException] the implementation throws.
  ///
  /// @throws [AtIOException] for any exception during the operation
  Future<void> write(String data);

  /// Write raw bytes, without waiting for them to leave.
  ///
  /// For a caller streaming a payload it has already encoded. Deliberately
  /// does **not** touch [AtConnectionMetaData.lastAccessed], matching what
  /// writing straight to the socket has always done.
  void add(List<int> bytes);

  /// The bytes arriving from the far end.
  ///
  /// Single-subscription, and the transport's own stream rather than a
  /// re-broadcast of it, so pausing this subscription reaches the far end.
  Stream<List<int>> get inbound;

  /// closes the underlying connection
  Future<void> close();

  /// Returns true if the connection is invalid
  bool isInValid();

  /// Gets the connection metadata
  AtConnectionMetaData? getMetaData();
}

abstract class AtConnectionMetaData {
  bool isAuthenticated = false;
  DateTime? lastAccessed;
  DateTime? created;
  bool isClosed = false;
  bool isStale = false;
  String? authenticatedAsEnrollmentId;
  DateTime? authenticatedAt;
}
