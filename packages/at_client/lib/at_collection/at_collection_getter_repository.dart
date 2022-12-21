import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

class AtCollectionGetterRepository<T> {
  final _logger = AtSignLogger('AtCollectionGetterRepository');

  @visibleForTesting
  AtClient? atClient;

  late KeyMakerSpec keyMaker;


  late String collectionName;
  final T Function(String jsonEncodedString) convert;

  AtCollectionGetterRepository({required this.collectionName, 
      required this.convert, required this.keyMaker});

  AtClient _getAtClient() {
    atClient ??= AtClientManager.getInstance().atClient;
    return atClient!;
  }

  Future<List<T>> getAll() async {
    List<T> dataList = [];

    var collectionAtKeys = await _getAtClient().getAtKeys(regex: collectionName);
    collectionAtKeys.retainWhere((atKey) => atKey.sharedWith == null);

    /// TODO: can there be a scenario when key is available but we can't get data
    /// In that scenario we might have to give failure results to app.
    for (var atKey in collectionAtKeys) {
      try {
        var atValue = await _getAtClient().get(atKey);
        var data = convert(atValue.value);
        dataList.add(data);
      } catch (e) {
        _logger.severe('failed to get value of ${atKey.key}');
      }
    }

    return dataList;
  }

  Future<T> getById(String keyId) async {
    AtKey atKey = keyMaker.createSelfKey(
      keyId: keyId,
      collectionName: collectionName,
    );

    try {
      AtValue atValue = await _getAtClient().get(atKey);
      var modelData = convert(atValue.value);
      return modelData;
    } catch (e) {
      _logger.severe('failed to get value of ${atKey.key}');
      rethrow;
    }
  }
}