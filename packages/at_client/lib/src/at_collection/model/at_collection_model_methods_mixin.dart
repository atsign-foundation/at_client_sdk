import 'package:at_client/src/at_collection/model/at_collection_impl.dart';
import 'package:at_client/src/at_collection/model/at_collection_model.dart';

mixin AtCollectionModelMethods on AtCollectionModel {
  AtCollectionImpl? atCollectionImpl;

  init() {
    atCollectionImpl ??= AtCollectionImpl(
      collectionName: collectionName,
      convert: convert,
    );
  }

  Future<bool> save({int? expiryTime}) async {
    init();
    return await atCollectionImpl!.save(this, expiryTime: expiryTime);
  }

  Future<List<AtDataStatus>> update() async {
    init();
    return await atCollectionImpl!.update(this);
  }

  Future<List<AtDataStatus>> delete() async {
    init();
    return await atCollectionImpl!.delete(this);
  }

  share() {}

  unshare() {}

  Future<List<String>> getSharedWithList() async {
    init();
    return await atCollectionImpl!.getSharedWithList(this);
  }
}
