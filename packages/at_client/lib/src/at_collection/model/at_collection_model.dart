import 'package:at_client/src/at_collection/model/at_collection_impl.dart';
import 'package:uuid/uuid.dart';

mixin ModelAddOn on AtCollectionModel {
  late AtCollectionImpl atCollectionImpl;
  save() {
    AtCollectionImpl atCollectionImpl =
        AtCollectionImpl(collectionName: collectionName);

    atCollectionImpl.save(this);
  }
}

abstract class AtCollectionModel {
  late String keyId;
  late String collectionName;

  AtCollectionModel({required this.collectionName}) {
    keyId = Uuid().v4();
  }

  Map<String, dynamic> toJson();
}

///TODO: remove after testing
// class Model extends AtCollectionModel with ModelAddOn {}

// func() {
//   Model m = Model();
//   m.save();
// }
