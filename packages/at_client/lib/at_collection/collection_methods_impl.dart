import 'package:at_client/at_collection/at_collection_model.dart';
import 'package:at_client/at_collection/collection_util.dart';
import 'package:at_client/at_collection/model/at_operation_item_status.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// [CollectionMethodImpl] have the implementation of all the methods available in collections package.
/// These methods are wrapped with a stream or future return types for the end consumption.

class CollectionMethodImpl {
  final _logger = AtSignLogger('AtCollectionModelMethodsImpl');

  AtClientManager? atClientManager;

  late KeyMakerSpec keyMaker = DefaultKeyMaker();
  AtCollectionModel atCollectionModel;

  CollectionMethodImpl(this.atCollectionModel);

  Stream<AtOperationItemStatus> save(
      {required String jsonEncodedData,
      ObjectLifeCycleOptions? options,
      bool share = false}) async* {
    options ??= ObjectLifeCycleOptions();
    String formattedId = CollectionUtil.format(atCollectionModel.id);
    String formattedCollectionName = CollectionUtil.format(
      atCollectionModel.getCollectionName(),
    );

    AtKey atKey = keyMaker.createSelfKey(
      keyId: formattedId,
      collectionName: formattedCollectionName,
      objectLifeCycleOptions: options,
    );

    var atOperationItemStatus = AtOperationItemStatus(
        atSign: atKey.sharedBy ?? '',
        key: atKey.key ?? '',
        complete: false,
        operation: Operation.save);
    try {
      var res = await _put(atKey, jsonEncodedData);
      atOperationItemStatus.complete = res;
      yield atOperationItemStatus;
    } catch (e) {
      atOperationItemStatus.complete = false;
      atOperationItemStatus.exception = Exception(e.toString());
      yield atOperationItemStatus;
    }

    if (share && atOperationItemStatus.complete == true) {
      yield* updateSharedKeys(
          formattedId, formattedCollectionName, jsonEncodedData);
    }
  }

  Stream<AtOperationItemStatus> updateSharedKeys(String formattedId,
      String formattedCollectionName, String jsonEncodedData) async* {
    var sharedAtKeys = await _getAtClient().getAtKeys(
        regex: CollectionUtil.makeRegex(
      formattedId: formattedId,
      collectionName: formattedCollectionName,
    ));

    sharedAtKeys.retainWhere((element) => element.sharedWith != null);

    for (var sharedKey in sharedAtKeys) {
      var atOperationItemStatus = AtOperationItemStatus(
          atSign: sharedKey.sharedWith ?? '',
          key: sharedKey.key ?? '',
          complete: false,
          operation: Operation.share);
      try {
        /// If self key is not updated, we do not update the shared keys
        var res = await _put(
          sharedKey,
          jsonEncodedData,
        );

        atOperationItemStatus.complete = res;
        yield atOperationItemStatus;
      } catch (e) {
        atOperationItemStatus.exception = Exception(e.toString());
        yield atOperationItemStatus;
      }
    }
  }

  Stream<AtOperationItemStatus> shareWith(List<String> atSigns,
      {ObjectLifeCycleOptions? options,
      required String jsonEncodedData}) async* {
    options ??= ObjectLifeCycleOptions();
    // String formattedId = CollectionUtil.format(atCollectionModel.id);
    String formattedId = atCollectionModel.id;
    String formattedCollectionName =
        CollectionUtil.format(atCollectionModel.getCollectionName());

    var selfKey = keyMaker.createSelfKey(
      keyId: formattedId,
      collectionName: formattedCollectionName,
      objectLifeCycleOptions: options,
    );

    late AtOperationItemStatus selfKeyUpdateStatus;
    await save(jsonEncodedData: jsonEncodedData, options: options, share: false)
        .forEach((AtOperationItemStatus event) {
      selfKeyUpdateStatus = event;
    });

    yield selfKeyUpdateStatus;

    // if success, then proceed to share
    for (var atSign in atSigns) {
      if (selfKeyUpdateStatus.complete == false) {
        continue; // if self key is not saved, we do not share
      }

      var sharedAtKey = keyMaker.createSharedKey(
          keyId: formattedId,
          collectionName: formattedCollectionName,
          objectLifeCycleOptions: options,
          sharedWith: atSign);

      var atOperationItemStatus = AtOperationItemStatus(
          atSign: atSign,
          key: selfKey.key ?? '',
          complete: false,
          operation: Operation.share);

      try {
        var res = await _put(sharedAtKey, jsonEncodedData);
        atOperationItemStatus.complete = res;
        yield atOperationItemStatus;
      } catch (e) {
        atOperationItemStatus.exception = Exception(e.toString());
        yield atOperationItemStatus;
        _logger.severe("Error in sharing $atSign $e");
      }
    }
  }

  Stream<AtOperationItemStatus> delete() async* {
    // String formattedId = CollectionUtil.format(atCollectionModel.id);
    String formattedId = atCollectionModel.id;
    String formattedCollectionName =
        CollectionUtil.format(atCollectionModel.getCollectionName());

    AtKey selfAtKey = keyMaker.createSelfKey(
      keyId: formattedId,
      collectionName: formattedCollectionName,
    );

    var isSelfKeyDeleted = await _getAtClient().delete(selfAtKey);

    yield AtOperationItemStatus(
        atSign: selfAtKey.sharedWith ?? '',
        key: selfAtKey.key ?? '',
        complete: isSelfKeyDeleted,
        operation: Operation.delete);
  }

  Stream<AtOperationItemStatus> unshare({List<String>? atSigns}) async* {
    // String formattedId = CollectionUtil.format(atCollectionModel.id);
    String formattedId = atCollectionModel.id;
    String formattedCollectionName = CollectionUtil.format(
      atCollectionModel.getCollectionName(),
    );

    var sharedAtKeys = await _getAtClient().getAtKeys(
      regex: CollectionUtil.makeRegex(
        formattedId: formattedId,
        collectionName: formattedCollectionName,
      ),
    );

    if (atSigns == null) {
      sharedAtKeys.retainWhere((element) => element.sharedWith != null);
    } else {
      sharedAtKeys
          .retainWhere((element) => atSigns.contains(element.sharedWith));
    }

    for (var sharedKey in sharedAtKeys) {
      var atOperationItemStatus = AtOperationItemStatus(
          atSign: sharedKey.sharedWith ?? '',
          key: sharedKey.key ?? '',
          complete: false,
          operation: Operation.unshare);

      try {
        var res = await _getAtClient().delete(sharedKey);
        atOperationItemStatus.complete = res;
        yield atOperationItemStatus;
      } catch (e) {
        atOperationItemStatus.exception = Exception(e.toString());
        yield atOperationItemStatus;
        _logger.severe("Error in deleting $sharedKey $e");
      }
    }
  }

  AtClient _getAtClient() {
    atClientManager ??= AtClientManager.getInstance();
    return atClientManager!.atClient;
  }

  Future<bool> _put(AtKey atKey, String jsonEncodedData) async {
    return await _getAtClient().put(
      atKey,
      jsonEncodedData,
    );
  }
}
