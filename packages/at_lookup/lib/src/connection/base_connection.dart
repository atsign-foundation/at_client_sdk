import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_utils/at_logger.dart';

/// Base class for common socket operations
abstract class BaseConnection extends AtConnection {
  late final AtSignLogger logger;
  late final Socket _socket;
  StringBuffer? buffer;
  AtConnectionMetaData? metaData;

  BaseConnection(Socket? socket) {
    logger = AtSignLogger(runtimeType.toString());
    buffer = StringBuffer();
    socket?.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket!;
  }

  @override
  AtConnectionMetaData? getMetaData() {
    return metaData;
  }

  @override
  Future<void> close() async {
    if (getMetaData()!.isClosed) {
      logger.finer('close(): connection is already closed');
      return;
    }

    try {
      var address = _socket.remoteAddress;
      var port = _socket.remotePort;

      logger.info('close(): calling socket.destroy()'
          ' on connection to $address:$port');
      _socket.destroy();
    } catch (e) {
      // Ignore errors or exceptions on a connection close
      logger.finer('Exception "$e" while destroying socket - ignoring');
      getMetaData()!.isStale = true;
    } finally {
      getMetaData()!.isClosed = true;
    }
  }

  @override
  Socket getSocket() {
    return _socket;
  }

  @override
  Future<void> write(String data) async {
    if (isInValid()) {
      //# Replace with specific exception
      throw ConnectionInvalidException('write(): Connection is invalid');
    }
    try {
      getSocket().write(data);
      await getSocket().flush();
      getMetaData()!.lastAccessed = DateTime.now().toUtc();
    } on Exception {
      getMetaData()!.isStale = true;
      rethrow;
    }
  }
}
