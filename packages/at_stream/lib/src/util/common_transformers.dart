// Transforms the sink from List<int> to Uint8List
import 'dart:async' show StreamTransformer;
import 'dart:typed_data' show Uint8List;

import 'package:async/async.dart' show StreamSinkTransformer;

class CommonTransformers {
  static final StreamSinkTransformer<Uint8List, List<int>>
      listIntToUint8ListSink = StreamSinkTransformer.fromStreamTransformer(
    StreamTransformer.fromBind((s) => s.map((u) => u.toList())),
  );

  static final StreamTransformer<List<int>, Uint8List>
      listIntToUint8ListStream =
      StreamTransformer.fromBind((s) => s.map(Uint8List.fromList));
}
