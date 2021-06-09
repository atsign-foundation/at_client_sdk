import 'dart:io';
import 'package:at_client/src/connection/at_connection.dart';

/// Base class for common socket operations
abstract class BaseConnection extends AtConnection {
  final Socket _socket;
  StringBuffer? buffer;
  AtConnectionMetaData? metaData;

  BaseConnection(this._socket) {
    buffer = StringBuffer();
  }

  @override
  AtConnectionMetaData? getMetaData() {
    return metaData;
  }

  @override
  void close() async {
    try {
      await _socket.close();
      getMetaData()!.isClosed = true;
    } on Exception {
      getMetaData()!.isStale = true;
      // Ignore exception on a connection close
    } on Error {
      getMetaData()!.isStale = true;
      // Ignore error on a connection close
    }
  }

  @override
  Socket getSocket() {
    return _socket;
  }

  @override
  void write(String data) async {
    if (isInvalid()) {
      //# Replace with specific exception
      throw Exception('Connection is invalid');
    }
    try {
      getSocket().write(data);
//      await getSocket().flush(); causing bad state..stream sink issue
      getMetaData()!.lastAccessed = DateTime.now().toUtc();
    } on Exception {
      getMetaData()!.isStale = true;
    }
  }
}
