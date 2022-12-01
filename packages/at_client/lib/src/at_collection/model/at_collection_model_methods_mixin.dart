import 'package:at_client/src/at_collection/model/at_collection_impl.dart';
import 'package:at_client/src/at_collection/model/at_collection_model.dart';

mixin AtCollectionModelMethods on AtCollectionModel {
  late AtCollectionImpl? atCollectionImpl;
  init() {
    atCollectionImpl = AtCollectionImpl(
      collectionName: collectionName,
      convert: convert,
    );
  }

  save({int? expiryTime}) {
    init();
    atCollectionImpl?.save(
      this,
      expiryTime: expiryTime,
    );
  }

  getAllData() {
    init();
    atCollectionImpl?.getAllData();
  }

  getDataById(String id, {String? sharedWith}) {
    init();
    atCollectionImpl?.getDataById(id, sharedWith: sharedWith);
  }
}
