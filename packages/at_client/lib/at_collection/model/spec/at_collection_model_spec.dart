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

  /// [id] is used to uniquely identify a model.
  /// It is auto generated and should not be changed.
  late String id;

  /// [convert] is function that accepts json encoded [String] and forms an instance of [AtCollectionModel].
  // final AtCollectionModelSpec Function(String jsonEncodedString) convert;

  /// [toJson] converts [AtCollectionModel] to a map format.
  /// App has to override this method and add all class members to it.
  ///
  /// e.g We have a class that extends [AtCollectionModel] and has name and description as it's member.
  ///
  /// Remember to mention [id] and [collectionName] in toJson.
  ///
  /// For such a class toJson would look like:
  ///
  /// ```
  ///   @override
  ///   Map<String, dynamic> toJson() {
  ///   final Map<String, dynamic> data = {};
  ///   data['id'] = id;
  ///   data['collectionName'] = collectionName;
  ///
  ///   data['name'] = name;
  ///   data['description'] = description;
  ///
  //   return data;
  // }
  /// ```
  ///
  Map<String, dynamic> toJson();

  T fromJson(String jsonDecodedData);

  /// Saves the object. If it is previously shared with bunch of @sign then it does reshare as well.
  /// However if you want the object to be just saved and want to share later then pass share as false
  /// If true is passed for share but the @signs to share with were never given then no share happens.
  Future<bool> save({bool share = true, ObjectLifeCycleOptions? options});

  /// Shares with these additional atSigns.
  Future<bool> share(List<String> atSigns, {ObjectLifeCycleOptions? options});

  /// unshares object with the list of atSigns supplied.
  /// If no @sign is passed, it is unshared with every one with whom it was previously shared with
  Future<bool> unshare({List<String>? atSigns});

  /// Returns a list of @sign with whom it was previously shared with
  Future<List<String>> getSharedWith();

  /// Deletes this object and unshares with everyone with whom it is previosly shared with
  Future<bool> delete();

  String getId();

  String getCollectionName();
}
