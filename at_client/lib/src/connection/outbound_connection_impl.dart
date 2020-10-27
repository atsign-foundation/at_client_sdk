import 'dart:io';
import 'outbound_connection.dart';

class OutboundConnectionImpl extends OutboundConnection {
  @override
  StringBuffer buffer;

  //#TODO move to config
  static int outbound_idle_time = 600000;

  OutboundConnectionImpl(Socket socket) : super(socket) {
    metaData = OutboundConnectionMetadata()..created = DateTime.now().toUtc();
  }

  int _getIdleTimeMillis() {
    var lastAccessedTime = getMetaData().lastAccessed;
    lastAccessedTime ??= getMetaData().created;
    var currentTime = DateTime.now().toUtc();
    return currentTime.difference(lastAccessedTime).inMilliseconds;
  }

  bool _isIdle() {
    return _getIdleTimeMillis() > outbound_idle_time;
  }

  @override
  bool isInvalid() {
    return _isIdle() || getMetaData().isClosed || getMetaData().isStale;
  }
}
