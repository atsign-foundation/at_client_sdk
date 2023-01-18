import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';

class DefaultKeyMaker implements KeyMakerSpec {
  AtClientManager? atClientManager;

  AtClient _getAtClient() {
    atClientManager ??= AtClientManager.getInstance();
    return atClientManager!.atClient;
  }

  @override
  AtKey createSelfKey(
      {required String keyId,
      required String collectionName,
      ObjectLifeCycleOptions? objectLifeCycleOptions}) {
    return AtKey()
      ..key = '$keyId.$collectionName'
      ..metadata = Metadata()
      ..metadata!.ccd = objectLifeCycleOptions?.cascadeDelete ?? true
      ..metadata!.ttl = objectLifeCycleOptions?.timeToLive?.inMilliseconds
      ..metadata!.ttb = objectLifeCycleOptions?.timeToBirth?.inMilliseconds
      ..sharedBy = _getAtClient().getCurrentAtSign();
  }

  @override
  AtKey createSharedKey(
      {required String keyId,
      required String collectionName,
      String? sharedWith,
      ObjectLifeCycleOptions? objectLifeCycleOptions}) {
    int? ttrInSeconds =
        objectLifeCycleOptions?.cacheRefreshIntervalOnRecipient?.inSeconds;

    return AtKey()
      ..key = '$keyId.$collectionName'
      ..sharedWith = sharedWith
      ..metadata = Metadata()
      ..metadata!.ttr = ttrInSeconds ?? -1
      ..metadata!.ccd = ttrInSeconds != null ? true : false
      ..metadata!.ttl = objectLifeCycleOptions?.timeToLive?.inMilliseconds
      ..metadata!.ttb = objectLifeCycleOptions?.timeToBirth?.inMilliseconds
      ..sharedBy = _getAtClient().getCurrentAtSign();
  }
}
