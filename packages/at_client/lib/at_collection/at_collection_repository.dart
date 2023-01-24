// import 'dart:mirrors';

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/collection_util.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_utils.dart';

class AtCollectionRepository {
  final _logger = AtSignLogger('AtCollectionRepository');

  AtClientManager? atClientManager;

  late KeyMakerSpec keyMaker;

  late String _collectionName;

  AtCollectionRepository({required this.keyMaker});

  AtClient getAtClient() {
    atClientManager ??= AtClientManager.getInstance();
    return atClientManager!.atClient;
  }

  Future<List<T>> getModelsByCollectionName<T extends AtCollectionModel>(
      {String? collectionName,
      required AtCollectionModelFactory<T> collectionModelFactory}) async {
    _collectionName = collectionName ?? T.toString().toLowerCase();
    _collectionName = CollectionUtil.format(_collectionName);
    var regex = CollectionUtil.makeRegex(
      collectionName: _collectionName,
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
            _collectionName != atValueJson['collectionName']) {
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

  Future<T> getModelById<T extends AtCollectionModel>(String keyId,
      {String? collectionName,
      required AtCollectionModelFactory<T> collectionModelFactory}) async {
    _collectionName = collectionName ?? T.toString().toLowerCase();

    String formattedId = CollectionUtil.format(keyId);
    String formattedCollectionName = CollectionUtil.format(_collectionName);

    AtKey atKey = keyMaker.createSelfKey(
      keyId: formattedId,
      collectionName: formattedCollectionName,
    );

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

  Future<List<T>> getModelsSharedWith<T extends AtCollectionModel>(
      String atSign) async {
    var regex = CollectionUtil.makeRegex();

    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == atSign);

    return _getAtCollectionModelsFromAtKey(collectionAtKeys);
  }

  Future<List<T>> getModelsSharedBy<T extends AtCollectionModel>(
      String atSign) async {
    var regex = CollectionUtil.makeRegex();

    var collectionAtKeys = await getAtClient().getAtKeys(regex: regex);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedBy == atSign);

    return _getAtCollectionModelsFromAtKey(collectionAtKeys);
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

        var factory = AtCollectionModelFactoryManager.getInstance()
            .get(atValueJson['collectionName']);
        var model = factory?.create();
        if (model == null) {
          continue;
        }

        model.fromJson(atValue.value);
        model.id = atValueJson['id'];
        model.collectionName = atValueJson['collectionName'];
        modelList.add(model as T);
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }

    return modelList;
  }
}
