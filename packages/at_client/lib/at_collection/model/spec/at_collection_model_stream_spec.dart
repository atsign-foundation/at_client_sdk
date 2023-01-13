import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/at_operation_item_status.dart';
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
abstract class AtCollectionModelStreamSpec<T> {
  AtCollectionModelStreamSpec();

  /// Saves the object. If it is previously shared with bunch of @sign then it does reshare as well.
  /// However if you want the object to be just saved and want to share later then pass share as false
  /// If true is passed for share but the @signs to share with were never given then no share happens.
  Stream<AtOperationItemStatus> save(
      {bool share = true, ObjectLifeCycleOptions? options});

  /// Shares with these additional atSigns.
  Stream<AtOperationItemStatus> share(List<String> atSigns,
      {ObjectLifeCycleOptions? options});

  /// unshares object with the list of atSigns supplied.
  /// If no @sign is passed it is unshared with every one with whom it was previously shared with
  Stream<AtOperationItemStatus> unshare({List<String>? atSigns});

  // Deletes this object completely and unshares with everyone with whom it is previosly shared with
  Stream<AtOperationItemStatus> delete();
}
