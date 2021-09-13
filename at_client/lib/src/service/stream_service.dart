import 'package:at_client/src/stream/at_stream.dart';
abstract class StreamService {

  /// Create a stream for a given [streamType]. If your app is sending a file through stream
  /// then pass [StreamType.SEND]. If your app is receiving a file pass [StreamType.RECEIVE].
  /// Optionally pass [streamId] if you want to create a stream for a known stream transfer.
  AtStream createStream(StreamType streamType, {String? streamId});
}