import 'dart:io';

abstract class AtConnection {
  /// Write a data to the underlying socket of the connection
  /// @param - data - Data to write to the socket
  /// @throws [AtIOException] for any exception during the operation
  void write(String data);

  /// Retrieves the socket of underlying connection
  Socket getSocket();

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

  /// The enrollment id this connection authenticated as, or null where the
  /// authentication carried none — a CRAM authentication, or a PKAM
  /// authentication made without one.
  ///
  /// This is what the connection *holds*, not what the next authentication
  /// will ask for. `AtLookUp.enrollmentId` is the latter: setting it does not
  /// move a socket that is already up, so a client whose enrollment changes
  /// must re-authenticate each connection and read this field back to know it
  /// happened.
  String? authenticatedAsEnrollmentId;

  /// When this connection last completed authentication, in UTC. Null until it
  /// authenticates; set on the same paths as [isAuthenticated].
  DateTime? authenticatedAt;
}
