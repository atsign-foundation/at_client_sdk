import 'dart:io' show Socket;
import 'dart:typed_data' show Uint8List;

import 'package:at_stream/src/stream_channel_sources/common_transformers.dart'
    show CommonTransformers;
import 'package:stream_channel/stream_channel.dart';

// Turns a Socket which is a Stream<Uint8List>, StreamSink<List<int>>
// into a StreamChannel<Uint8List>
extension StreamChannelSocket on Socket {
  StreamChannel<Uint8List> toStreamChannel() {
    return StreamChannel<Uint8List>(
      this,
      CommonTransformers.listIntToUint8ListSink.bind(this),
    );
  }
}
