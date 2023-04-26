import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/at_collection_model_stream.dart';
import 'package:at_client/at_collection/at_collection_repository.dart';
import 'package:at_client/at_collection/collection_methods_impl.dart';
import 'package:at_client/at_collection/collection_util.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';
import 'dart:convert';
import 'package:meta/meta.dart';

/// implementation of [AtCollectionModelSpec]
abstract class AtCollectionModel<T> extends AtCollectionModelSpec {
  final _logger = AtSignLogger('AtCollectionModel');

  static KeyMakerSpec keyMaker = DefaultKeyMaker();

  AtClientManager? atClientManager;

  late AtCollectionModelStream streams;
  static AtCollectionRepository atCollectionRepository = AtCollectionRepository(
    keyMaker: keyMaker,
  );

  late CollectionMethodImpl collectionMethodImpl;

  AtCollectionModel() {
    collectionMethodImpl = CollectionMethodImpl(this);
    streams = AtCollectionModelStream(
      atCollectionModel: this,
      keyMaker: keyMaker,
      collectionMethodImpl: collectionMethodImpl,
    );
  }

  set setKeyMaker(KeyMakerSpec newKeyMaker) {
    keyMaker = newKeyMaker;
    collectionMethodImpl.keyMaker = keyMaker;
  }

  AtClient _getAtClient() {
    atClientManager ??= AtClientManager.getInstance();
    return atClientManager!.atClient;
  }

  /// The method getById() returns a AtCollectionModel object whose id property matches the specified string.
  /// The id property is internally matched with an [AtKey] that is used to save the object.
  ///
  /// Since element IDs are expected to be unique if specified, they're a useful way to get retrieve a AtCollectionModel quickly.
  ///
  /// The id property can be set by assigning a value to [AtCollectionModel.id].
  ///
  /// If you do not know the id of your AtCollectionModel, then call getAll static method to get all of the AtCollectionModel objects for a given collectionName.
  /// collectionName  is an optional parameter when the getById is called with the Type information.

  /// Ex:
  /// ```
  /// class Phone extends AtCollectionModel {
  ///        // Implementation
  ///
  ///       Phone();
  ///
  ///       Phone.from(String id){
  ///       id = this.id;
  ///   }
  ///
  /// }
  /// ```
  ///
  /// Creating a phone object with `personal phone` as id
  ///
  /// ```
  /// Phone personaPhone = await Phone.from('personal phone').save();
  /// ```
  /// ```
  /// class PhoneModelFactory extends AtCollectionModelFactory
  ///  {
  ///      @override
  ///       Phone create() {
  ///         return Phone();
  ///       }
  /// }
  /// ```
  ///
  /// Usage without collectionName is being passed:
  ///
  /// ```
  /// PhoneModelFactory phoneFactory = PhoneModelFactory();
  /// var personalPhone = await AtCollectionModel.getById<Phone>(‘Personal Phone’, phoneFactory);
  /// ```
  /// Usage with collectionName is being passed:
  ///
  /// ```
  /// PhoneModelFactory phoneFactory = PhoneModelFactory();
  /// var personalPhone = AtCollectionModel.getById(‘Personal Phone’, ‘Phone’, phoneFactory);
  /// ```
  ///
  /// An Exception will be thrown if AtCollectionModel object with a given Id can not be found.

  static Future<T> getModelById<T extends AtCollectionModel>(
    String id, {
    String? collectionName,
  }) async {
    if (!Collections.getInstance().isInitialized) {
      throw Exception(
          'Initialization is required. Invoke initialize method on Collection object');
    }

    return (await atCollectionRepository.getModelById<T>(id,
        collectionName: collectionName));
  }

  /// The [getModelsByCollectionName] method of AtCollectionModel returns an list of AtCollectionModels that have a given collection name.
  ///
  /// Ex:
  /// ```
  /// class Phone extends AtCollectionModel {
  ///        // Implementation
  ///
  ///       Phone();
  ///
  ///       Phone.from(String id){
  ///       id = this.id;
  ///   }
  ///
  /// }
  /// ```
  ///
  /// Creating two phone object with `personal phone` and `office phone` as their respective id.
  ///
  /// ```
  /// Phone personalPhone = await Phone.from('personal phone').save();
  /// Phone officePhone = await Phone.from('office phone').save();
  /// ```
  /// ```
  /// class PhoneModelFactory extends AtCollectionModelFactory
  ///  {
  ///      @override
  ///       Phone create() {
  ///         return Phone();
  ///       }
  /// }
  /// ```
  ///
  /// Usage without collectionName is being passed:
  ///
  /// ```
  /// PhoneModelFactory phoneFactory = PhoneModelFactory();
  /// List<Phone> phoneList = await AtCollectionModel.getAll<Phone>(phoneFactory);
  /// ```
  ///
  /// Usage with collectionName is being passed:
  ///
  /// ```
  /// PhoneModelFactory phoneFactory = PhoneModelFactory();
  /// List<Phone> phoneList = AtCollectionModel.getAll(‘Phone’, phoneFactory);
  ///
  /// for(var phone in phoneList){
  ///   print(phone.id);
  ///  }
  /// ```
  ///
  /// Returns an empty list when there are no AtCollectionModel objects found for the given collectionName.
  static Future<List<T>> getModelsByCollectionName<T extends AtCollectionModel>(
      {String? collectionName}) async {
    if (!Collections.getInstance().isInitialized) {
      throw Exception(
          'Initialization is required. Invoke initialize method on Collection object');
    }

    return (await atCollectionRepository.getModelsByCollectionName<T>(
      collectionName: collectionName,
    ));
  }

  /// returns list of AtCollectionModel shared with the the given [atSign]
  ///
  /// e.g
  /// ```
  /// class Phone extends AtCollectionModel { }
  /// class Home extends AtCollectionModel { }
  ///
  /// await Phone().share(['@kevin']);
  /// await Home().share(['@kevin']);
  ///
  /// var allSharedModels = await AtCollectionModel.getModelsSharedWith(atSign : '@kevin');
  /// ```
  ///  allSharedModels will have objects of both Phone and Home
  static Future<List<T>> getModelsSharedWith<T extends AtCollectionModel>(
      String atSign) async {
    if (!Collections.getInstance().isInitialized) {
      throw Exception(
          'Initialization is required. Invoke initialize method on Collection object');
    }

    AtUtils.formatAtSign(atSign)!;
    return (await atCollectionRepository.getModelsSharedWith<T>(atSign));
  }

  /// returns list of AtCollectionModel shared by the given [atSign].
  ///
  /// e.g
  /// ```
  /// class Phone extends AtCollectionModel { }
  /// class Home extends AtCollectionModel { }
  ///
  ///```
  /// If @kevin shares Phone and Home objects with current @sign
  ///```
  /// await Phone().share(['@sign']);
  /// await Home().share(['@sign']);
  ///
  /// var allReceivedModels = await AtCollectionModel.getModelsSharedBy(atSign : '@kevin');
  /// ```
  ///  allSharedModels will have objects of both Phone and Home
  static Future<List<T>> getModelsSharedBy<T extends AtCollectionModel>(
      String atSign) async {
    if (!Collections.getInstance().isInitialized) {
      throw Exception(
          'Initialization is required. Invoke initialize method on Collection object');
    }
    AtUtils.formatAtSign(atSign)!;
    return (await atCollectionRepository.getModelsSharedBy<T>(atSign));
  }

  @override
  Future<bool> save(
      {bool share = true, ObjectLifeCycleOptions? options}) async {
    var jsonObject = CollectionUtil.initAndValidateJson(
      collectionModelJson: toJson(),
      id: collectionId,
      collectionName: getCollectionName(),
    );

    final Completer<bool> completer = Completer<bool>();

    bool? isSelfKeySaved, isAllKeySaved = true;

    await collectionMethodImpl
        .save(
            jsonEncodedData: jsonEncode(jsonObject),
            options: options,
            share: share)
        .forEach((AtOperationItemStatus atOperationItemStatus) {
      /// save will update self key as well as the shared keys
      /// the first event that will be coming in the stream would be the AtOperationItemStatus of selfKey
      isSelfKeySaved ??= atOperationItemStatus.complete;

      if (atOperationItemStatus.complete == false) {
        isAllKeySaved = false;
      }
    });

    if (share == false) {
      completer.complete(isSelfKeySaved);
      return isSelfKeySaved ?? false;
    }

    completer.complete(isAllKeySaved);
    return completer.future;
  }

  @override
  Future<List<String>> getSharedWith() async {
    CollectionUtil.validateIdAndCollectionName(
      collectionId,
      getCollectionName(),
    );

    List<String> sharedWithList = [];
    String formattedId = CollectionUtil.format(collectionId);
    String formattedCollectionName = CollectionUtil.format(getCollectionName());

    var allKeys = await _getAtClient().getAtKeys(
        regex: CollectionUtil.makeRegex(
      formattedId: formattedId,
      collectionName: formattedCollectionName,
    ));

    for (var atKey in allKeys) {
      if (atKey.sharedWith != null) {
        sharedWithList.add(atKey.sharedWith!);
      }
    }

    return sharedWithList;
  }

  @override
  Future<bool> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options}) async {
    var jsonObject = CollectionUtil.initAndValidateJson(
      collectionModelJson: toJson(),
      id: collectionId,
      collectionName: getCollectionName(),
    );

    List<AtOperationItemStatus> allSharedKeyStatus = [];
    await collectionMethodImpl
        .shareWith(atSigns,
            jsonEncodedData: jsonEncode(jsonObject), options: options)
        .forEach((element) {
      allSharedKeyStatus.add(element);
    });

    bool allOpeartionSuccessful = true;
    for (var sharedKeyStatus in allSharedKeyStatus) {
      if (sharedKeyStatus.complete == false) {
        allOpeartionSuccessful = false;
        break;
      }
    }
    return allOpeartionSuccessful;
  }

  @override
  Future<bool> delete() async {
    CollectionUtil.validateIdAndCollectionName(
        collectionId, getCollectionName());

    bool isSelfKeyDeleted = false;
    await collectionMethodImpl
        .delete()
        .forEach((AtOperationItemStatus operationEvent) {
      if (operationEvent.complete) {
        isSelfKeyDeleted = true;
      }
    });

    if (!isSelfKeyDeleted) {
      return false;
    }

    /// unsharing all shared keys.
    bool isAllShareKeysUnshared = true;

    await collectionMethodImpl
        .unshare()
        .forEach((AtOperationItemStatus operationEvent) {
      if (operationEvent.complete == false) {
        isAllShareKeysUnshared = false;
      }
    });

    return isAllShareKeysUnshared;
  }

  @override
  Future<bool> unshare({List<String>? atSigns}) async {
    bool isAllShareKeysUnshared = true;

    await collectionMethodImpl
        .unshare(atSigns: atSigns)
        .forEach((AtOperationItemStatus operationEvent) {
      if (operationEvent.complete == false) {
        isAllShareKeysUnshared = false;
      }
    });

    return isAllShareKeysUnshared;
  }

  @override
  String getCollectionName() {
    return collectionName ?? runtimeType.toString().toLowerCase();
  }
}
