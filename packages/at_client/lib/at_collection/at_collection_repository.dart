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

  Future<List<T>> getAll<T extends AtCollectionModel>(
      {String? collectionName,
      required AtCollectionModelFactory<T> collectionModelFactory}) async {
    _collectionName = collectionName ?? T.toString().toLowerCase();

    List<T> modelList = [];

    var collectionAtKeys =
        await getAtClient().getAtKeys(regex: _collectionName);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == null);

    for (var atKey in collectionAtKeys) {
      try {
        var atValue = await getAtClient().get(atKey);
        var atValueJson = jsonDecode(atValue.value);
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

  Future<T> getById<T extends AtCollectionModel>(String keyId,
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
}
