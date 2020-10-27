import 'dart:io';
import 'package:at_client/src/connection/at_connection.dart';
import 'package:at_client/src/connection/base_connection.dart';

abstract class OutboundConnection extends BaseConnection {
  OutboundConnection(Socket socket) : super(socket);
}

/// Metadata information for [OutboundConnection]
class OutboundConnectionMetadata extends AtConnectionMetaData {}
