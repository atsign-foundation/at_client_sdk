import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';

abstract class KeyMakerSpec {
  AtKey createSelfKey({required String keyId, required String collectionName, 
      ObjectLifeCycleOptions? objectLifeCycleOptions});

  AtKey createSharedKey({required String keyId, required String collectionName,  
      String? sharedWith, ObjectLifeCycleOptions? objectLifeCycleOptions});
}