import 'dart:mirrors';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

class AtCollectionRepository {
  final _logger = AtSignLogger('AtCollectionRepository');

  @visibleForTesting
  AtClient? atClient;

  late KeyMakerSpec keyMaker;

  late String _collectionName;

  AtCollectionRepository({required this.keyMaker});

  AtClient _getAtClient() {
    atClient ??= AtClientManager.getInstance().atClient;
    return atClient!;
  }

  T _convert<T extends AtCollectionModel>(String jsonDecodedData) {
    T t = ClassActivator.createInstance(T);
    return t.fromJson(jsonDecodedData) as T;
  }

  Stream<T> getAll<T extends AtCollectionModel>(
      {String? collectionName}) async* {
    _collectionName = collectionName ?? T.toString().toLowerCase();

    List<T> dataList = [];

    var collectionAtKeys =
        await _getAtClient().getAtKeys(regex: _collectionName);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == null);

    /// TODO: can there be a scenario when key is available but we can't get data
    /// In that scenario we might have to give failure results to app.
    for (var atKey in collectionAtKeys) {
      try {
        var atValue = await _getAtClient().get(atKey);
        var data = _convert<T>(atValue.value);
        yield data;
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }
  }

  Future<T> getById<T extends AtCollectionModel>(String keyId,
      {String? collectionName}) async {
    _collectionName = collectionName ?? T.toString().toLowerCase();

    AtKey atKey = keyMaker.createSelfKey(
      keyId: keyId,
      collectionName: _collectionName,
    );

    try {
      AtValue atValue = await _getAtClient().get(atKey);
      var modelData = _convert<T>(atValue.value);
      return modelData;
    } catch (e) {
      _logger.severe('failed to get value of ${atKey.key}');
      rethrow;
    }
  }
}

class ClassActivator {
  static createInstance(Type type,
      [Symbol? constructor,
      List? arguments,
      Map<Symbol, dynamic>? namedArguments]) {
    constructor ??= const Symbol("");
    arguments ??= const [];

    var typeMirror = reflectType(type);
    if (typeMirror is ClassMirror) {
      return typeMirror
          .newInstance(constructor, arguments, (namedArguments ?? {}))
          .reflectee;
    } else {
      throw ArgumentError("Cannot create the instance of the type '$type'.");
    }
  }
}
