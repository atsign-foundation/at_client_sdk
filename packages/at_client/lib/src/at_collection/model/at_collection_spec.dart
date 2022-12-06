import 'package:at_client/at_client.dart';
import 'package:at_client/src/at_collection/model/at_collection_impl.dart';
import 'package:at_client/src/at_collection/model/at_collection_model.dart';
import 'package:at_client/src/at_collection/model/at_share_operation.dart';
import 'package:at_client/src/at_collection/model/at_unshare_operation.dart';

abstract class AtCollectionSpec<T extends AtCollectionModel> {
  /// Used to save the model in a self key
  /// a unique ID is generated and stored in [T.id]
  /// returns true if operation was successful else returns false
  /// [expiryTime] Represents the time in milliseconds beyond which the key expires
  Future<bool> save(T model, {int? expiryTime});

  /// updates the [T] data using [T.id] as identifier
  /// if [T.id] is null, throws [Exception]
  ///
  /// Also, updates all the associated data with [T.id] if it has been shared with mutiple atSigns
  /// returns false if failes to update any key, self or shared.
  Future<List<AtDataStatus>> update(T model, {int? expiryTime});

  /// returns all unique data for [T.collectionName]
  /// unique data is identified as the self keys which are not shared with any atSign
  ///
  /// If an AtKey (1234.collection@alice) has been shared with bob (@bob:1234.collection@alice)
  /// [getAllData] will only return single copy of (1234.collection@alice)
  /// we assume all data with same [T.id] are same
  Future<List<T>> getAllData();

  /// returns [T] by finding the value by [key]
  /// returns null if value could not be fetched
  /// throws KeyNotFoundException if key does not exists
  Future<T?> getById(String id, {String sharedWith});

  /// deletes all the keys associated with [T.id]
  ///
  /// e.g alice's self key - 1234.collection@alice
  /// shared with bob - @bob1234.collection@alice
  ///
  /// both the keys will be deleted as they have the same ID (1234.collection)
  ///
  /// returns Map<String, AtDataStatus> where String stores atSign and AtDataStatus has the status of the operation.
  Future<List<AtDataStatus>> delete(T model);

  /// TODO: change the approach to use stream based sharing.
  /// shares [T.id]'s value with [atSignsList]
  /// creates a new copy of data for every atSign in the list
  ///
  /// if 1234.collection@alice is being shared with @bob
  /// a new copy will be created as
  /// @bob:1234.collection@alice
  ///
  /// returns Map<String, AtDataStatus> where String is the atSign and AtDataStatus has the status of share
  ///
  /// throws [exception] if [T.keyId] is null
  AtShareOperation share(T model, List<String> atSignsList);

  /// deletes shared keys with [atSignsList]
  AtUnshareOperation unShare(T model, List<String> atSignsList);

  /// returns List of String that the data [T] is shared with
  /// If [T.id] does not exists on key store throws [KeyNotFoundException]
  Future<List<String>> getSharedWithList(T model);

  // Future<bool> notify(T data, List<String> atSigns);
}

// create, update, delete, notify, store by reference
