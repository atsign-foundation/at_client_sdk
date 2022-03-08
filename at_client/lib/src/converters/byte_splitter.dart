import 'dart:convert';
import 'dart:typed_data';

class Splitter extends Converter<List<int>, List<List<int>>> {
  Splitter(this._splitOnByte);

  final int _splitOnByte;

  @override
  SplitterSink startChunkedConversion(Sink sink) {
    return SplitterSink(sink, _splitOnByte);
  }

  @override
  List<List<int>> convert(input) {
    var out = ListSink();
    var sink = SplitterSink(out, _splitOnByte);
    sink.add(input);
    sink.close();
    return out.list;
  }
}

class SplitterSink extends ByteConversionSinkBase {
  SplitterSink(this._sink, this._splitOnByte);

  final int _splitOnByte;
  final Sink _sink;

  @override
  void add(List<int> chunk) {
    assert(chunk is Uint8List);
    for (var i = 0; i < chunk.length; i += _splitOnByte) {
      _sink.add(chunk.sublist(i,
          i + _splitOnByte > chunk.length ? chunk.length : i + _splitOnByte));
    }
  }

  @override
  void close() {
    _sink.close();
  }
}

class ListSink extends Sink<List<int>> {
  final List<List<int>> list = <List<int>>[];
  @override
  void add(List<int> data) => list.add(data);

  @override
  void close() {}
}
