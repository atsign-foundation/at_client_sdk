import 'package:at_client/at_client.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/stream/at_stream_response.dart';

class StreamManager {
  late String _atSign;
  static final Map<String, StreamManager> _syncManagerMap = {};

  late AtClientPreference preference;

  RemoteSecondary? remoteSecondary;

  factory StreamManager.getInstance(String atSign) {
    if (_syncManagerMap.containsKey(_syncManagerMap)) {
      return _syncManagerMap[atSign]!;
    }
    final syncManager = StreamManager._internal(atSign);
    _syncManagerMap[atSign] = syncManager;
    return syncManager;
  }

  StreamManager._internal(this._atSign);

  /// onDone[AtStreamResponse]
  /// onError[AtStreamResponse]
  Future<void> send(
  String sharedWith, String filePath, Function onDone, Function onError) async {

  }

  Future<void> resume(
      String sharedWith, String filePath, int startByte, Function onDone, Function onError) async {

  }

  Future<void> cancel(String streamId) async {

  }

  Future<void> streamAck(
      String streamId,
      String fileName,
      int fileLength,
      String senderAtSign,
      Function streamCompletionCallBack,
      Function streamReceiveCallBack) async {

  }
}
