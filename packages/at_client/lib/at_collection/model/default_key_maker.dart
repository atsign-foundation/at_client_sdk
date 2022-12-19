import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';

class DefaultKeyMaker implements KeyMakerSpec {
  AtClient? atClient;

  AtClient _getAtClient() {
    atClient ??= AtClientManager.getInstance().atClient;
    return atClient!;
  }
  
  @override
  AtKey createSelfKey({required String keyId, required String collectionName, 
    ObjectLifeCycleOptions? objectLifeCycleOptions}) {
    return AtKey()
      ..key = '$keyId.$collectionName'
      ..metadata = Metadata()
      ..metadata!.ttr = -1
      ..metadata!.ttl = objectLifeCycleOptions?.timeToLive?.inMilliseconds
      ..metadata!.ttb = objectLifeCycleOptions?.timeToBirth?.inMilliseconds
      ..sharedBy = _getAtClient().getCurrentAtSign();
  }

  @override
  AtKey createSharedKey({required String keyId, required String collectionName,  
      String? sharedWith, ObjectLifeCycleOptions? objectLifeCycleOptions}) {
    return AtKey()
      ..key = '$keyId.$collectionName'
      ..sharedWith = sharedWith
      ..metadata = Metadata()
      ..metadata!.ttr = -1
      ..metadata!.ttl = objectLifeCycleOptions?.timeToLive?.inMilliseconds
      ..metadata!.ttb = objectLifeCycleOptions?.timeToBirth?.inMilliseconds
      ..sharedBy = _getAtClient().getCurrentAtSign();
  }

}