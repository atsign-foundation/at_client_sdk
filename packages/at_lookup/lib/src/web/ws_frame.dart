import 'dart:convert';
import 'dart:typed_data';

/// The bytes of one received WebSocket frame: a text frame's UTF-8 encoding,
/// or a binary frame's contents.
List<int> frameBytes(Object? data) => switch (data) {
      String() => utf8.encode(data),
      ByteBuffer() => Uint8List.view(data),
      List<int>() => data,
      _ => throw ArgumentError.value(
          data, 'data', 'not a WebSocket frame payload (${data.runtimeType})'),
    };
