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

      logger.finer('close(): calling socket.destroy()'
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

  @Deprecated('Read through BaseConnection.inbound and write raw bytes '
      'through BaseConnection.add(). Removed in 4.0.0.')
  @override
  Socket getSocket() {
    return _socket;
  }

  /// The bytes arriving from the far end: the socket, so pausing a
  /// subscription to it reaches the far end.
  ///
  /// Cast, not just upcast: the socket is a `Stream<Uint8List>`, and through
  /// the wider type `transform(utf8.decoder)` and `pipe(sink)` would pass
  /// analysis and then fail their run-time check against `Uint8List`.
  Stream<List<int>> get inbound => getSocket().cast<List<int>>();

  /// Writes raw bytes, without waiting for them to leave.
  ///
  /// Unlike [write], does not update [AtConnectionMetaData.lastAccessed].
  void add(List<int> bytes) => getSocket().add(bytes);

  @override
  Future<void> write(String data) async {
    final lineFeed = data.indexOf('\n');
    if (lineFeed >= 0 && lineFeed != data.length - 1) {
      throw IllegalArgumentException('a command is one line, and this one '
          'holds a line feed at offset $lineFeed of ${data.length}');
    }
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
