import 'dart:convert';


import 'package:at_client/at_collection/impl/default_key_maker.dart';
import 'package:at_utils/at_logger.dart';
import '../../at_client.dart';
import '../collection_util.dart';
import '../collections.dart';

class AtCollectionQueryOperationsImpl extends AtCollectionQueryOperations {
  final _logger = AtSignLogger('AtCollectionQueryOperationsImpl');
  AtClientManager? atClientManager;
  final KeyMaker _keyMaker = DefaultKeyMaker();

  AtCollectionQueryOperationsImpl();

  AtClient getAtClient() {
    atClientManager ??= AtClientManager.getInstance();
    return atClientManager!.atClient;
  }

  @override
  Future<List<T>> getModelsByCollectionName<T extends AtCollectionModel>(
      String collectionName) async {
    AtCollectionModelFactory<T>? collectionModelFactory  =
        AtCollectionModelFactoryManager.getInstance().get(collectionName);

    if (collectionModelFactory == null) {
      throw Exception('Factory class not found for the given $collectionName');
    }

    var formattedCollectionName = CollectionUtil.format(collectionName);
    var regex = CollectionUtil.makeRegex(
      collectionName: formattedCollectionName,
    );

    List<T> modelList = [];

    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == null);

    for (var atKey in collectionAtKeys) {
      try {
        var atValue = await getAtClient().get(atKey);
        var atValueJson = jsonDecode(atValue.value);

        /// Given that id and collectionName attributes are not present, it is not a atcollectionmodel. Ignore it.
        /// OR there is a collectionName but it is not what is asked hence ignore it.
        if (atValueJson['id'] == null ||
            atValueJson['collectionName'] == null ||
            formattedCollectionName != atValueJson['collectionName']) {
          continue;
        }

        T model = collectionModelFactory.create();
        _populateModel(model, atValueJson, atKey);
        modelList.add(model);
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }

    return modelList;
  }

  @override
  Future<T> getModel <T extends AtCollectionModel>(
      String id, String namespace, String collectionName) async {
    AtCollectionModelFactory<T>? collectionModelFactory =
        AtCollectionModelFactoryManager.getInstance().get(collectionName);

    if (collectionModelFactory == null) {
      throw Exception('Factory class not found for the given $collectionName');
    }

    String formattedId = CollectionUtil.format(id);
    String formattedCollectionName = CollectionUtil.format(collectionName);

    AtKey atKey = _keyMaker.createSelfKey(
        keyId: formattedId,
        collectionName: formattedCollectionName,
        namespace: namespace);

    try {
      AtValue atValue = await getAtClient().get(atKey);
      var atValueJson = jsonDecode(atValue.value);
      T model = collectionModelFactory.create();
      _populateModel(model, jsonDecode(atValue.value), atKey);
      return model;
    } catch (e) {
      _logger.severe('failed to get value of ${atKey.key} $e');
      throw Exception('AtCollectionModel is not found for the given id:$id , namespace:$namespace and collectionName: $collectionName');
    }
  }

  @override
  Future<List<T>> getModelsSharedWith<T extends AtCollectionModel>(String atSign) async {
    var regex = CollectionUtil.makeRegex();

    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == atSign);

    return _getAtCollectionModelsFromAtKey(collectionAtKeys);
  }

  @override
  Future<List<T>> getModelsSharedBy<T extends AtCollectionModel>(String atSign) async {
    var regex = CollectionUtil.makeRegex();
    // Get all collection model keys
    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    // Just keep the ones where shared by is the atSign passed
    collectionAtKeys.retainWhere((atKey) => (atKey.sharedBy != null && atKey.sharedBy == atSign));


    return _getAtCollectionModelsFromAtKey(collectionAtKeys);
  }

  @override
  Future<List<T>> getModelsSharedByAnyAtSign<T extends AtCollectionModel>() async {
    var regex = CollectionUtil.makeRegex();
    // Get all collection model keys
    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    // From all of the shared collection keys retain the ones where sharedBy is not null and it not the current atSign
    collectionAtKeys.retainWhere((atKey) => (atKey.sharedBy != null && atKey.sharedBy != getAtClient().getCurrentAtSign()));
    return _getAtCollectionModelsFromAtKey(collectionAtKeys);
  }


  @override
  Future<List<T>>
      getModelsSharedWithAnyAtSign<T extends AtCollectionModel>() async {
    var regex = CollectionUtil.makeRegex();
    // Get all collection model keys
    List<AtKey> collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    // Just keep the keys that current atSign has shared
    collectionAtKeys.retainWhere((atKey) => (atKey.sharedBy != null &&
        atKey.sharedBy == getAtClient().getCurrentAtSign() &&
        atKey.sharedWith != null));
    Set<AtKey> uniqueSelfKeys = {};
    // Add distinct keys that are shared to the other atSigns.
    // Removing the sharedWith atSign and adding each key to set to fetch the
    // distinct keys.
    for (AtKey atKey in collectionAtKeys) {
      atKey.sharedWith = null;
      uniqueSelfKeys.add(atKey);
    }
    return _getAtCollectionModelsFromAtKey(uniqueSelfKeys.toList());
  }

  Future<List<T>> _getAtCollectionModelsFromAtKey<T extends AtCollectionModel>(
      List<AtKey> collectionAtKeys) async {
    List<T> modelList = [];

    for (var atKey in collectionAtKeys) {
      try {
        var atValue = await getAtClient().get(atKey);
        var atValueJson = jsonDecode(atValue.value);

        /// Given that id and collectionName attributes are not present, it is not a atcollectionmodel. Ignore it.
        /// OR there is a collectionName but it is not what is asked hence ignore it.
        if (atValueJson['id'] == null ||
            atValueJson['collectionName'] == null) {
          continue;
        }


        AtCollectionModelFactory<AtCollectionModel>? factory = AtCollectionModelFactoryManager.getInstance()
            .get(atValueJson['collectionName']);

        T? model = factory?.create() as T?;
        if (model == null) {
          continue;
        }

        _populateModel(model, atValueJson, atKey);
        model.sharedByAtSign = atKey.sharedBy!;
        modelList.add(model);
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }

    return modelList;
  }

  void _populateModel(AtCollectionModel model, Map<String, dynamic> atValueJson, AtKey atKey) {
    model.id = atValueJson['id'];
    model.collectionName = atValueJson['collectionName'];
    model.namespace = CollectionUtil.getNamespaceFromKey(atKey.toString());
    model.fromJson(atValueJson);
  }
}


