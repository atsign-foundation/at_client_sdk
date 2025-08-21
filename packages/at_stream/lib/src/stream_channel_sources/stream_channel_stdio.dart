import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:at_stream/src/util/common_transformers.dart';
import 'package:stream_channel/stream_channel.dart'
    show StreamChannelMixin, StreamChannel;

class StreamChannelStdio
    with StreamChannelMixin<Uint8List>
    implements StreamChannel<Uint8List> {
  final IOSink _sink;
  final Stream<List<int>> _stream;

  // There is a gotcha here, stdout and stdin can be flipped
  // depending on if it's for this process or another process.
  // Hence the very explicit factories even though they aren't really needed.
  const StreamChannelStdio._(this._stream, this._sink);

  /// Used when you want to hook into the stdio of THIS process.
  factory StreamChannelStdio.currentProcess() {
    return StreamChannelStdio._(stdin, stdout);
  }

  /// Used when you want to hook into the stdio of ANOTHER process
  factory StreamChannelStdio.otherProcess(
    Stream<List<int>> stdout,
    IOSink stdin,
  ) {
    return StreamChannelStdio._(stdout, stdin);
  }

  @override
  StreamSink<Uint8List> get sink =>
      CommonTransformers.listIntToUint8ListSink.bind(_sink);

  @override
  Stream<Uint8List> get stream =>
      CommonTransformers.listIntToUint8ListStream.bind(_stream);
}
