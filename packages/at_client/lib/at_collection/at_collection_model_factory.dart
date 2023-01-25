import 'package:at_client/at_client.dart';

abstract class AtCollectionModelFactory<T extends AtCollectionModel> {
  AtCollectionModelFactory() {
    AtCollectionModelFactoryManager.getInstance().register(this);
  }

  /// Expected to return an instance of T
  T create();

  /// returns [true] if the factory creates instances of atCollectionModel for the given [collectionName]
  bool acceptCollection(String collectionName) {
    return collectionName == T.toString().toLowerCase();
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
    collectionFactories.add(factory);
  }

  AtCollectionModelFactory? get(String collectionName) {
    for (AtCollectionModelFactory collectionFactory in collectionFactories) {
      if (collectionFactory.acceptCollection(collectionName)) {
        return collectionFactory;
      }
    }
    return null;
  }
}

// Provides collection framework with the list of factory classes that creates collection models
class Collections {
  static final Collections _singleton = Collections._internal();

  Collections._internal();

  factory Collections.getInstance() {
    return _singleton;
  }

  bool isInitialized = false;

  void initialize(List<AtCollectionModelFactory> factories) {
    isInitialized = true;
  }
}
