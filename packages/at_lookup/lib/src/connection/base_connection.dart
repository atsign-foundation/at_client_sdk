import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_lookup/src/transport/at_transport.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

/// Throws `IllegalArgumentException` when [command] holds a line feed anywhere
/// but its last character, since the atServer ends a command at a line feed.
///
/// The message gives the line feed's offset and the command's length, and no
/// part of the command.
void requireOneLine(String command) {
  final lineFeed = command.indexOf('\n');
  if (lineFeed >= 0 && lineFeed != command.length - 1) {
    throw IllegalArgumentException('a command is one line, and this one '
        'holds a line feed at offset $lineFeed of ${command.length}');
  }
}

/// Base class for common transport operations
abstract class BaseConnection extends AtConnection {
  late final AtSignLogger logger;
  final AtTransport _transport;
  StringBuffer? buffer;
  AtConnectionMetaData? metaData;

  /// Non-nullable: the previous `AtTransport?` parameter was dereferenced with
  /// `!` on the next line, so a null argument was already a crash - stated in
  /// the signature rather than discovered at runtime.
  BaseConnection(this._transport) {
    logger = AtSignLogger(runtimeType.toString());
    buffer = StringBuffer();
  }

  @override
  AtConnectionMetaData? getMetaData() => metaData;

  /// Whether the transport under this connection can still carry bytes.
  @protected
  bool get isTransportOpen => _transport.isOpen;

  /// The transport's inbound stream, cast rather than upcast: a socket's is a
  /// `Stream<Uint8List>`, and through the wider type `transform(utf8.decoder)`
  /// and `pipe(sink)` would pass analysis and then fail their run-time check
  /// against `Uint8List`. A pause still reaches the transport.
  @override
  Stream<List<int>> get inbound => _transport.inbound.cast<List<int>>();

  @override
  Future<void> close() async {
    if (getMetaData()!.isClosed) {
      logger.finer('close(): connection is already closed');
      return;
    }
    try {
      logger.finer('close(): calling destroy()'
          ' on connection to ${_transport.description}');
      _transport.destroy();
    } catch (e) {
      logger.finer('Exception "$e" while destroying transport - ignoring');
      getMetaData()!.isStale = true;
    } finally {
      getMetaData()!.isClosed = true;
    }
  }

  @override
  void add(List<int> bytes) => _transport.add(bytes);

  /// Writes [data] and flushes it.
  ///
  /// Fails as [requireOneLine] does, writing nothing, when [data] is not one
  /// line.
  @override
  Future<void> write(String data) async {
    requireOneLine(data);
    if (isInValid()) {
      throw ConnectionInvalidException('write(): Connection is invalid');
    }
    try {
      _transport.add(utf8.encode(data));
      await _transport.flush();
      getMetaData()!.lastAccessed = DateTime.now().toUtc();
    } on Exception {
      getMetaData()!.isStale = true;
      rethrow;
    }
  }
}
