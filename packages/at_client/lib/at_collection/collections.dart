
import '../at_client.dart';

/// Contains CRUD operations that can be performed on [AtCollectionModel]
abstract class AtCollectionModelOperations {
  /// Saves the json representaion of the object to the secondary server of the @sign.
  /// [save] calls [toJson] method to get the json representation of a [AtCollectionModel].
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
  Future<bool> save({bool share = true, ObjectLifeCycleOptions? options});

  /// [share] shares the AtCollectionModel object with the @signs in [atSigns] list.
  ///
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var res = await personalPhone.share(['@kevin', '@colin']);
  /// ```
  ///
  /// Returns true, if all the share operation is successful else returns false.
  /// If fine grained information on individual operations that happens within [share] is desired then use [streams.share]
  Future<bool> share(List<String> atSigns, {ObjectLifeCycleOptions? options});

  /// [unshare] unshares the AtCollectionModel object with the @signs in [atSigns] list.
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
  Future<List<String>> getSharedWith();

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
  fromJson(String jsonObject);
}

/// Contains query methods on [AtCollectionModel]
abstract class AtCollectionQueryOperations {
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
  Future<List<AtCollectionModel>> getModelsSharedBy(String atSign);

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
  Future<List<AtCollectionModel>> getModelsSharedWith(String atSign);

  /// The method getById() returns a AtCollectionModel object whose id property matches the specified string.
  /// The id property is internally matched with an [AtKey] that is used to save the object.
  ///
  /// Since element IDs are expected to be unique if specified, they're a useful way to get retrieve a AtCollectionModel quickly.
  ///
  /// The id property can be set by assigning a value to [AtCollectionModel.id].
  ///
  /// If you do not know the id of your AtCollectionModel, then call getAll static method to get all of the AtCollectionModel objects for a given collectionName.
  /// collectionName is an optional parameter when the getById is called with the Type information.

  /// Ex:
  /// ```
  /// class Phone extends AtCollectionModel {
  /// // Implementation
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
  /// {
  ///      @override
  ///   Phone create() {
  ///     return Phone();
  ///   }
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
  Future<AtCollectionModel> getModel(String id, String namespace, String collectionName);

  /// The [getModelsByCollectionName] method of AtCollectionModel returns an list of AtCollectionModels that have a given collection name.
  ///
  /// Ex:
  /// ```
  /// class Phone extends AtCollectionModel {
  /// // Implementation
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
  /// {
  ///      @override
  /// Phone create() {
  ///  return Phone();
  /// }
  /// }
  /// ```
  ///
  /// var phoneModels = getModelsByCollectionName('phone');
  /// ```
  ///  phoneModels will have personalPhone and officePhone
  ///
  /// Returns an empty list when there are no AtCollectionModel objects found for the given collectionName.
  Future<List<AtCollectionModel>> getModelsByCollectionName(String collectionName);
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
  AtKey createSelfKey({required String keyId, required String collectionName, required String namespace,
    ObjectLifeCycleOptions? objectLifeCycleOptions});

  AtKey createSharedKey({required String keyId, required String collectionName, required String namespace,
    String? sharedWith, ObjectLifeCycleOptions? objectLifeCycleOptions});
}

class ObjectLifeCycleOptions {
  // How long the object is supposed to live
  Duration? timeToLive;

  // when the object becomes available
  Duration? timeToBirth;

  /// If set to true, delete operation will delete recipient's  cached key also
  bool cascadeDelete;

  Duration cacheRefreshIntervalOnRecipient;

  bool cacheValueOnRecipient;

  ObjectLifeCycleOptions(
      {this.timeToBirth,
        this.timeToLive,
        this.cascadeDelete = true,
        this.cacheValueOnRecipient = true,
        this.cacheRefreshIntervalOnRecipient = const Duration(days: 5)});
}



