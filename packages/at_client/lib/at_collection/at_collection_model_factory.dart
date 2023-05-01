import 'package:at_client/at_client.dart';

abstract class AtCollectionModelFactory<T extends AtCollectionModel> {
  /// Expected to return an instance of T
  T create();

  /// returns [true] if the factory creates instances of atCollectionModel for the given [collectionName]
  bool acceptCollection(String collectionName) {
    return collectionName == T.toString().toLowerCase();
  }

  // In case of conflict priority is used to resolve the right factory for a given collection name
  int priority() {
    return 10;
  }
}

class AtCollectionModelFactoryManager {
  static final AtCollectionModelFactoryManager _singleton =
      AtCollectionModelFactoryManager._internal();

  AtCollectionModelFactoryManager._internal();

  factory AtCollectionModelFactoryManager.getInstance() {
    return _singleton;
  }

  List<AtCollectionModelFactory> collectionFactories = [];

  register(AtCollectionModelFactory factory) {
    if(!collectionFactories.contains(factory)) {
      collectionFactories.add(factory);
    }
  }

  AtCollectionModelFactory? get(String collectionName) {
    AtCollectionModelFactory? maxPriorityCollectionFactory;
    for (AtCollectionModelFactory collectionFactory in collectionFactories) {
      if (collectionFactory.acceptCollection(collectionName)) {
        if(maxPriorityCollectionFactory != null && collectionFactory.priority() > maxPriorityCollectionFactory.priority()) {
          maxPriorityCollectionFactory = collectionFactory;
        } else {
          maxPriorityCollectionFactory = collectionFactory;
        }
      }
    }
    return maxPriorityCollectionFactory;
  }
}

