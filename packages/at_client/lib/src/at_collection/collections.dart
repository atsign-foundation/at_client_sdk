import 'package:at_client/at_client.dart';

/// Contains CRUD operations that can be performed on [AtCollectionModel]
abstract class AtCollectionModelOperations {
  /// Saves the json representation of [AtCollectionModel] to the secondary server of a atSign.
  /// [save] calls [toJson] method to get the json representation of a [AtCollectionModel].
  ///
  /// If [autoReshare] is set to true, then the Object will not only be saved but also be shared with the atSigns with whom it was previously shared.
  ///
  /// If [autoReshare] is set to false, then the object is not shared till the [autoReshare] method is called.
  ///
  /// Pass [options] to control lifecycle of the object.
  ///
  /// Usage
  /// ```
  /// class Phone extends AtCollectionModel {
  ///  // Implementation
  /// }
  /// ```
  ///
  /// Creating phone objects without [options]
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// Phone officePhone = await Phone('office phone').save();
  /// ```
  /// Creating a phone objects with [options]
  ///
  /// phone object that lives only for 24 hrs.
  /// ```
  /// Phone temporaryPhone = await Phone('temporary phone').save(options : ObjectLifeCycleOptions(timeToLive : Duration(hours : 24)));
  /// ```
  /// By default the value shared is cached on the recipient, if this has to changed then set objectLifeCycleOptions [cacheValueOnRecipient] to fasle.
  /// By default when the object is deleted then the cached values on the recipients are deleted. if this needs to be changed set [objectLifeCycleOptions.cascadeDelete] to false.
  ///
  /// Returns a true if save is successful else returns a false.
  /// If fine grained information on individual operations that happens within [save] is desired then use [streams.save]
  Future<bool> save({bool autoReshare = true, ObjectLifeCycleOptions? options});

  /// [share] shares the AtCollectionModel object with the atSigns in [atSigns] list.
  ///
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var res = await personalPhone.share(['@kevin', '@colin']);
  /// ```
  ///
  /// Returns true, if all the share operation is successful else returns false.
  /// If fine grained information on individual operations that happens within [share] is desired then use [streams.share]
  Future<bool> share(List<String> atSigns, {ObjectLifeCycleOptions? options});

  /// [unshare] unshares the AtCollectionModel object with the atSigns in [atSigns] list.
  ///
  /// If [atSigns] is not passed then AtCollectionModel object is unshared with every @sign it was previously shared.
  ///
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var sahreRes = await personalPhone.share(['@kevin', '@colin']);
  /// var unshareRes = await personalPhone.unshare(['@kevin']);
  /// ```
  ///
  /// Returns true, if all the unshare operation is successful else returns false.
  /// If fine grained information on individual operations that happens within [unshare] is desired then use [streams.unshare]
  ///
  Future<bool> unshare({List<String>? atSigns});

  /// Returns a list of @sign with whom AtCollectionModel object is shared with
  ///
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var sahreRes = await personalPhone.share(['@kevin', '@colin']);
  /// var sharedList = await personalPhone.getSharedWith();
  /// ```
  ///
  /// Returns an empty list when object is not shared.
  Future<List<String>> sharedWith();

  /// Deletes the object and unshares with every @sign it was shared with previously
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var sahreRes = await personalPhone.share(['@kevin', '@colin']);
  /// var sharedList = await personalPhone.delete();
  /// ```
  Future<bool> delete();

  /// [toJson] method returns JSON representation of the object.
  /// The [save] method invokes this method to get the state which will be persisted to the secondary server.
  ///
  /// class that extends AtCollectionModel has to override this method.
  ///
  /// e.g We have a class that extends [AtCollectionModel] and has name and description as it's member.
  ///
  /// For such a class toJson would look like:
  ///
  /// ```
  ///   @override
  ///   Map<String, dynamic> toJson() {
  ///   final Map<String, dynamic> data = {};
  ///   data['name'] = name;
  ///   data['description'] = description;
  ///   return data;
  /// }
  /// ```
  ///
  Map<String, dynamic> toJson();

  /// Populated state of AtCollectionModel from its JSON representation.
  /// class that extends AtCollectionModel has to override this method to populate object's state.
  ///
  /// e.g We have a class that extends [AtCollectionModel] and has name and description as it's member.
  ///
  /// For such a class toJson would look like:
  /// ```
  ///   @override
  ///   fromJson(String jsonObject) {
  ///
  ///   this.name = jsonObject['name'];
  ///   this.description = jsonObject['description'];
  /// }
  /// ```
  ///
  /// [fromJson] will be internally used by [getById], [getAll] methods
  fromJson(Map<String, dynamic> jsonObject);
}

/// Contains query methods on [AtCollectionModel]
abstract class AtCollectionQueryOperations {
  /// Returns list of AtCollectionModels that are shared by the given [atSign]
  /// Returns an empty list when nothing has been shared
  ///
  /// Instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  Future<List<T>> getModelsSharedBy<T extends AtCollectionModel>(String atSign);

  /// Returns list of AtCollectionModels that are shared any atSign
  /// Returns an empty list when nothing has been shared
  ///
  /// Instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  Future<List<T>> getModelsSharedByAnyAtSign<T extends AtCollectionModel>();

  /// Returns list of AtCollectionModels that are shared with the given [atSign]
  /// Returns an empty list when nothing has been shared
  ///
  /// Instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  Future<List<T>> getModelsSharedWith<T extends AtCollectionModel>(
      String atSign);

  /// Returns list of AtCollectionModels that are shared with any atSign
  /// Returns an empty list when nothing has been shared
  ///
  /// Instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  Future<List<T>> getModelsSharedWithAnyAtSign<T extends AtCollectionModel>();

  /// Returns an instance of a class extending  [AtCollectionModel] for the given [id], [namespace] and [collectionName]
  /// An instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  ///
  /// Throws [Exception] when an AtCollectionModel could not found for the given inputs
  Future<T> getModel<T extends AtCollectionModel>(
      String id, String namespace, String collectionName);

  /// Returns list of AtCollectionModels that are created for the [collectionName] passed
  /// Returns an empty list when there are no matches
  ///
  /// An instance of [AtJsonCollectionModel] is returned If a specific factory class for a given collection name is not registered
  /// Factory class for a [collectionName] can be registered using method [AtCollectionModel.registerFactories(factories)]
  Future<List<T>> getModelsByCollectionName<T extends AtCollectionModel>(
      String collectionName);
}

/// [AtCollectionModel] sets the base structure of the model that is used to interact with collection methods.
///
/// To utilize it just create a class that extends [AtCollectionModel] and define your class members.
///
/// e.g
/// ```
/// class MyModel extends AtCollectionModel {}
/// ```
///
abstract class AtCollectionModelStreamOperations {
  /// Saves the json representaion of the object to the secondary server of the @sign.
  /// [save] calls [toJson] method to get the json representation.
  ///
  /// If [share] is set to true, then the Object will not only be saved but also be shared with the @signs with whom it was previously shared.
  ///
  /// If [share] is set to false, then the object is not shared till the [share] method is called.
  ///
  /// Pass [options] to control lifecycle of the object.
  ///
  /// Usage
  /// ```
  /// class Phone extends AtCollectionModel {
  /// // Implementation
  /// }
  /// ```
  ///
  /// Creating phone objects without [options]
  /// ```
  /// Phone('personal phone').streams.save().forEach(
  ///   (AtOperationItemStatus element) {
  ///    ///
  ///   },
  /// );
  ///
  /// Phone('office phone').streams.save().forEach(
  ///   (AtOperationItemStatus element) {
  ///    ///
  ///   },
  /// );
  /// ```
  /// Creating a phone objects with [options]
  ///
  /// phone object that lives only for 24 hrs.
  /// ```
  ///  Phone('temporary phone').streams.save(options : ObjectLifeCycleOptions(timeToLive : Duration(hours : 24))).forEach(
  ///   (AtOperationItemStatus element) {
  ///    ///
  ///   },
  /// );
  /// ```
  /// By default the value shared is cached on the recipient, if this has to changed then set objectLifeCycleOptions [cacheValueOnRecipient] to fasle.
  /// By default when the object is deleted then the cached values on the recipients are deleted. if this needs to be changed set [objectLifeCycleOptions.cascadeDelete] to false.
  ///
  /// Returns Stream<AtOperationItemStatus>, where [AtOperationItemStatus] represents status of individual operations.
  Stream<AtOperationItemStatus> save(
      {bool share = true, ObjectLifeCycleOptions? options});

  /// [share] shares the AtCollectionModel object with the @signs in [atSigns] list.
  ///
  /// ```
  /// await Phone('personal phone').save();
  /// personalPhone.streams.share([@kevin, @colin]).forEach(
  ///   (AtOperationItemStatus element) {
  ///    ///
  ///   },
  /// );
  /// ```
  ///
  /// Returns Stream<AtOperationItemStatus>, where [AtOperationItemStatus] represents status of individual operations.
  Stream<AtOperationItemStatus> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options});

  /// [unshare] unshares the AtCollectionModel object with the @signs in [atSigns] list.
  ///
  /// If [atSigns] is not passed then AtCollectionModel object is unshared with every @sign it was previously shared.
  ///
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var sahreRes = await personalPhone.share([@kevin, @colin]);
  /// personalPhone.streams.unshare([@kevin]).forEach(
  ///   (AtOperationItemStatus element) {
  ///     ///
  ///   },
  /// );
  /// ```
  ///
  /// Returns Stream<AtOperationItemStatus>, where [AtOperationItemStatus] represents status of individual operations.
  Stream<AtOperationItemStatus> unshare({List<String>? atSigns});

  /// Deletes the object and unshares with every @sign it was shared with previously
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var sahreRes = await personalPhone.share([@kevin, @colin]);
  /// personalPhone.streams.delete().forEach(
  ///   (AtOperationItemStatus element) {
  ///    ///
  ///   },
  /// );
  /// ```
  /// Returns Stream<AtOperationItemStatus>, where [AtOperationItemStatus] represents status of individual operations.
  Stream<AtOperationItemStatus> delete();
}

class AtOperationItemStatus {
  late String atSign;
  late String key;
  bool complete;
  Exception? exception;
  Operation? operation;

  AtOperationItemStatus({
    required this.atSign,
    required this.key,
    required this.complete,
    required this.operation,
    this.exception,
  });
}

enum Operation { save, share, unshare, delete }

abstract class KeyMaker {
  AtKey createSelfKey(
      {required String keyId,
      required String collectionName,
      required String namespace,
      ObjectLifeCycleOptions? objectLifeCycleOptions});

  AtKey createSharedKey(
      {required String keyId,
      required String collectionName,
      required String namespace,
      String? sharedWith,
      ObjectLifeCycleOptions? objectLifeCycleOptions});
}

class ObjectLifeCycleOptions {
  // How long the object is supposed to live
  Duration? timeToLive;

  // when the object becomes available
  Duration? timeToBirth;

  /// If set to true, delete operation will delete recipient's  cached key also
  bool cascadeDelete;

  /// Set value to true if the shared value needs to be cached on the recipient.
  bool cacheValueOnRecipient;

  // Time after which the recipient has to refresh the cached value that was shared by someone
  Duration cacheRefreshIntervalOnRecipient;

  ObjectLifeCycleOptions(
      {this.timeToBirth,
      this.timeToLive,
      this.cascadeDelete = true,
      this.cacheValueOnRecipient = true,
      this.cacheRefreshIntervalOnRecipient = const Duration(days: 5)});
}
