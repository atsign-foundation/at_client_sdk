import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/at_collection_model_stream.dart';
import 'package:at_client/at_collection/at_collection_repository.dart';
import 'package:at_client/at_collection/collection_methods_impl.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';
import 'package:at_client/at_collection/model/spec/key_maker_spec.dart';
import 'package:at_utils/at_logger.dart';
import 'dart:convert';
import 'package:meta/meta.dart';

/// implementation of [AtCollectionModelSpec]
abstract class AtCollectionModel<T> extends AtCollectionModelSpec {
  final _logger = AtSignLogger('AtCollectionModel');

  @visibleForTesting
  AtClient? atClient;

  static KeyMakerSpec keyMaker = DefaultKeyMaker();

  late AtCollectionModelStream streams = AtCollectionModelStream(
    atCollectionModel: this,
    keyMaker: keyMaker,
  );

  static AtCollectionRepository atCollectionRepository = AtCollectionRepository(
    keyMaker: keyMaker,
  );

  AtCollectionModel() {
    CollectionMethodImpl.getInstance().atCollectionModel = this;
  }

  set setKeyMaker(KeyMakerSpec newKeyMaker) {
    keyMaker = newKeyMaker;
    CollectionMethodImpl.getInstance().keyMaker = keyMaker;
  }

  AtClient _getAtClient() {
    atClient ??= AtClientManager.getInstance().atClient;
    return atClient!;
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

  static Future<T> getById<T extends AtCollectionModel>(String id,
      {String? collectionName,
      required AtCollectionModelFactory collectionModelFactory}) async {
    return (await atCollectionRepository.getById<T>(
      id,
      collectionName: collectionName,
      collectionModelFactory: collectionModelFactory,
    ));
  }

  /// The [getAll] method of AtCollectionModel returns an list of AtCollectionModels that have a given collection name.
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
  static Future<List<T>> getAll<T extends AtCollectionModel>(
      {String? collectionName,
      required AtCollectionModelFactory collectionModelFactory}) async {
    return (await atCollectionRepository.getAll<T>(
      collectionName: collectionName,
      collectionModelFactory: collectionModelFactory,
    ));
  }

  _initAndValidateJson() {
    Map<String, dynamic> objectJson = toJson();
    objectJson['id'] = id;
    objectJson['collectionName'] = getCollectionName();
    _validateModel(objectJson);
  }

  @override
  Future<bool> save(
      {bool share = true, ObjectLifeCycleOptions? options}) async {
    _initAndValidateJson();

    final Completer<bool> completer = Completer<bool>();

    bool? isSelfKeySaved, isAllKeySaved = true;

    await CollectionMethodImpl.getInstance()
        .save(
            jsonEncodedData: jsonEncode(toJson()),
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
    }

    completer.complete(isAllKeySaved);
    return completer.future;
  }

  @override
  Future<List<String>> getSharedWith() async {
    _initAndValidateJson();
    List<String> sharedWithList = [];

    var allKeys =
        await _getAtClient().getAtKeys(regex: '$id.${getCollectionName()}');

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
    _initAndValidateJson();

    List<AtOperationItemStatus> allSharedKeyStatus = [];
    await CollectionMethodImpl.getInstance()
        .shareWith(atSigns,
            jsonEncodedData: jsonEncode(toJson()), options: options)
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
    _initAndValidateJson();

    bool isSelfKeyDeleted = false;
    await CollectionMethodImpl.getInstance()
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

    await CollectionMethodImpl.getInstance()
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

    await CollectionMethodImpl.getInstance()
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
    return runtimeType.toString().toLowerCase();
  }

  /// Throws exception if id or collectionName is not added.
  _validateModel(Map<String, dynamic> objectJson) {
    if (id.trim().isEmpty) {
      throw Exception('id not found');
    }

    if (getCollectionName().trim().isEmpty) {
      throw Exception('collectionName not found');
    }

    if (objectJson['id'] == null) {
      throw Exception('id not added in toJson');
    }

    if (objectJson['collectionName'] == null) {
      throw Exception('collectionName not added in toJson');
    }
  }

  Future<bool> _put(AtKey atKey, String jsonEncodedData) async {
    return await _getAtClient().put(
      atKey,
      jsonEncodedData,
    );
  }
}
