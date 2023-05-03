import 'dart:convert';

import 'at_collection_model.dart';
import 'at_collection_model_factory.dart';

// Represens a generic JSON model of a atCollection model
class AtJsonCollectionModel extends AtCollectionModel {

  late Map<String, dynamic> jsonModel;

  @override
  fromJson(String jsonObject) {
    jsonModel = jsonDecode(jsonObject);
  }

  @override
  Map<String, dynamic> toJson() {
    return jsonModel;
  }


}

// Factory for creating instance of AtJsonCollectionModel
// Factory accepts ay collection name
class AtJsonCollectionModelFactory extends AtCollectionModelFactory {
  @override
  AtCollectionModel create() {
    return AtJsonCollectionModel();
  }

  @override
  bool acceptCollection(String collectionName) {
    return true;
  }

  @override
  int priority() {
    return 1;
  }
}

