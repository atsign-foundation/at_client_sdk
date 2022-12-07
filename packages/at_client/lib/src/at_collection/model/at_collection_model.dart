import 'package:uuid/uuid.dart';

/// [AtCollectionModel] sets the base structure of the model that is used to interact with collection methods.
///
/// To utilize it just create a class that extends [AtCollectionModel] and define your class members.
///
/// e.g
/// ```
/// class MyModel extends AtCollectionModel with AtCollectionModelMethods {}
/// ```
/// [AtCollectionModelMethods] allows to get all the methods available on [AtCollectionModel] like save, update, delete, share, unshare, getSharedWithList.
///
abstract class AtCollectionModel {
  /// [id] is used to uniquely identify a model.
  /// It is auto generated and should not be changed.
  late String id;

  /// [collectionName] is a unique name that is given to a class.
  /// Each objects of same class will have same collection name.
  ///
  /// e.g If alice is creating a class object with id - 123 and collectionName - house.
  ///
  /// key will be structured as 123.house@alice
  ///
  /// Similarly we can have multiple object instance -
  /// ```
  /// 12345.house@alice
  /// 12346.house@alice
  /// ```
  ///
  /// All these objects comes under same [collectionName] - house but have a unique [id]
  late String collectionName;

  /// [convert] is function that accepts json encoded [String] and forms an instance of [AtCollectionModel].
  final AtCollectionModel Function(String jsonEncodedString) convert;

  AtCollectionModel({required this.collectionName, required this.convert}) {
    id = Uuid().v4();
  }

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
}
