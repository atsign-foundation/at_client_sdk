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
}
