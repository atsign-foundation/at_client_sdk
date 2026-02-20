import 'dart:async';

import 'package:at_client/at_client.dart';

// MCP already uses JSON strings, there's no need to do anything
// special to encode our values here. The value that the MCP
// server uses is the same encoding as what we transmit

class SendTransformer extends StreamTransformerBase<String, String> {
  @override
  Stream<String> bind(Stream<String> stream) {
    return stream;
  }
}

class RecvTransformer
    extends StreamTransformerBase<(AtNotification, String), String> {
  @override
  Stream<String> bind(Stream<(AtNotification, String)> stream) {
    return stream.map((e) => e.$2);
  }
}
