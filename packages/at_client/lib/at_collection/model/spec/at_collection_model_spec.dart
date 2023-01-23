import 'package:at_client/at_client.dart';
import 'package:uuid/uuid.dart';
import 'package:at_client/at_collection/model/object_lifecycle_options.dart';

/// [AtCollectionModel] sets the base structure of the model that is used to interact with collection methods.
///
/// To utilize it just create a class that extends [AtCollectionModel] and define your class members.
///
/// e.g
/// ```
/// class MyModel extends AtCollectionModel {}
/// ```
///
abstract class AtCollectionModelSpec<T> {
  AtCollectionModelSpec() {
    id = Uuid().v4();
  }

  /// [id] uniquely identifies this model.
  ///
  /// By default, id is set to UUID.
  late String id;

  /// [collectionName] represents objects of same type.
  String? collectionName;

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
  ///        // Implementation
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
  /// var res = await personalPhone.share([@kevin, @colin]);
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
  /// var sahreRes = await personalPhone.share([@kevin, @colin]);
  /// var unshareRes = await personalPhone.unshare([@kevin]);
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
  /// var sahreRes = await personalPhone.share([@kevin, @colin]);
  /// var sharedList = await personalPhone.getSharedWith();
  /// ```
  ///
  /// Returns an empty list when object is not shared.
  Future<List<String>> getSharedWith();

  /// Deletes the object and unshares with every @sign it was shared with previously
  /// ```
  /// Phone personalPhone = await Phone('personal phone').save();
  /// var sahreRes = await personalPhone.share([@kevin, @colin]);
  /// var sharedList = await personalPhone.delete();
  /// ```
  Future<bool> delete();

  /// [getCollectionName] returns a string that identifies group of object of same kind.
  /// The value is default to the name of the class extenting AtCollectionModel.
  ///
  /// This method is internally used by AtCollectionModel methods to save and retrieve objects form secondary server of the current @sign.
  String getCollectionName();
}
