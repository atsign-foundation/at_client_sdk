import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_lookup/src/transport/at_transport.dart';
import 'package:at_utils/at_logger.dart';

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

  @override
  Stream<List<int>> get inbound => _transport.inbound;

  @override
  Future<void> close() async {
    if (getMetaData()!.isClosed) {
      logger.finer('close(): connection is already closed');
      return;
    }
    try {
      logger.info('close(): calling destroy()'
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

  @override
  Future<void> write(String data) async {
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
