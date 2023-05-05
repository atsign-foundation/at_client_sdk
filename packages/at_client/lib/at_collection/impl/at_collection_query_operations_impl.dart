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
  Future<List<AtCollectionModel>> getModelsByCollectionName(
      String collectionName) async {
    var collectionModelFactory =
        AtCollectionModelFactoryManager.getInstance().get(collectionName);

    if (collectionModelFactory == null) {
      throw Exception('Factory class not found for the given $collectionName');
    }

    var formattedCollectionName = CollectionUtil.format(collectionName);
    var regex = CollectionUtil.makeRegex(
      collectionName: formattedCollectionName,
    );

    List<AtCollectionModel> modelList = [];

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

        var model = collectionModelFactory.create();
        model.fromJson(atValue.value);
        model.id = atValueJson['id'];
        model.collectionName = atValueJson['collectionName'];
        modelList.add(model);
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }

    return modelList;
  }

  @override
  Future<AtCollectionModel> getModel(
      String id, String namespace, String collectionName) async {
    var collectionModelFactory =
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
      var model = collectionModelFactory.create();
      model.fromJson(atValue.value);
      model.id = atValueJson['id'];
      model.collectionName = atValueJson['collectionName'];
      return model;
    } catch (e) {
      _logger.severe('failed to get value of ${atKey.key}');
      rethrow;
    }
  }

  @override
  Future<List<AtCollectionModel>> getModelsSharedWith(String atSign) async {
    var regex = CollectionUtil.makeRegex();

    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == atSign);

    return _getAtCollectionModelsFromAtKey(collectionAtKeys);
  }

  @override
  Future<List<AtCollectionModel>> getModelsSharedBy(String atSign) async {
    var regex = CollectionUtil.makeRegex();

    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedBy == atSign);

    return _getAtCollectionModelsFromAtKey(collectionAtKeys);
  }

  Future<List<AtCollectionModel>>
      _getAtCollectionModelsFromAtKey<T extends AtCollectionModel>(
          List<AtKey> collectionAtKeys) async {
    List<AtCollectionModel> modelList = [];

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

        var factory = AtCollectionModelFactoryManager.getInstance()
            .get(atValueJson['collectionName']);
        var model = factory?.create();
        if (model == null) {
          continue;
        }

        model.fromJson(atValue.value);
        model.id = atValueJson['id'];
        model.collectionName = atValueJson['collectionName'];
        modelList.add(model);
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }

    return modelList;
  }
}
