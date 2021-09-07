import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/service/stream_service.dart';
import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/stream_handler.dart';
import 'package:at_utils/at_logger.dart';

class StreamServiceImpl implements StreamService, AtSignChangeListener {
  late AtClient _atClient;

  StreamServiceImpl._(this._atClient);

  static final Map<String, StreamService> _streamServiceMap = {};

  final _logger = AtSignLogger('StreamServiceImpl');

  static StreamService create(AtClient atClient) {
    if (_streamServiceMap.containsKey(atClient.getCurrentAtSign())) {
      return _streamServiceMap[atClient.getCurrentAtSign()]!;
    }
    _streamServiceMap[atClient.getCurrentAtSign()!] =
        StreamServiceImpl._(atClient);
    return _streamServiceMap[atClient.getCurrentAtSign()]!;
  }

  @override
  AtStream createStream(StreamType streamType, {String? streamId}) {
    var stream = StreamHandler.getInstance().createStream(
        _atClient.getCurrentAtSign()!, streamType,
        streamId: streamId);
    if (streamType == StreamType.SEND) {
      stream.sender!.remoteSecondary = RemoteSecondary(
          _atClient.getCurrentAtSign()!, _atClient.getPreferences()!);
      stream.sender!.encryptionService = _atClient.encryptionService;
    } else if (streamType == StreamType.RECEIVE) {
      stream.receiver!.encryptionService = _atClient.encryptionService;
      stream.receiver!.preference = _atClient.getPreferences()!;
      stream.receiver!.remoteSecondary = RemoteSecondary(
          _atClient.getCurrentAtSign()!, _atClient.getPreferences()!);
    }
    return stream;
  }

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    // TODO: clean up if any
  }
}
