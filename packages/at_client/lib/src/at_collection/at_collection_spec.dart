import 'package:at_client/at_client.dart';
import 'package:at_client/src/at_collection/at_collection_impl.dart';

abstract class AtCollectionSpec<T extends AtCollectionModel> {
  /// Saves the object [T] in a self key.
  /// A unique id is generated and stored in [T.id].
  ///
  /// Returns true if operation was successful else returns false.
  ///
  /// [expiryTime] Represents the time in milliseconds beyond which the key expires.
  Future<bool> save(T model, {int? expiryTime});

  /// updates object [T] using [T.id] as identifier.
  /// Throws [Exception], if [T.id] or [T.collectionName] is empty.
  ///
  /// [update] also takes care of updating all the associated data with [T.id] if it has been shared with mutiple atSigns.
  ///
  /// returns List<AtDataStatus>, where AtDataStatus represents update status of individual key.
  Future<List<AtDataStatus>> update(T model, {int? expiryTime});

  /// returns all unique data for [T.collectionName].
  ///
  /// unique data is identified as the self keys which are not shared with any atSign.
  ///
  /// If an AtKey (1234.collection@alice) has been shared with bob (@bob:1234.collection@alice)
  /// [getAllData] will only return single copy of (1234.collection@alice).
  ///
  /// we assume all objects with same [T.id] are same.
  Future<List<T>> getAllData();

  /// returns [T] by finding the value by [id]
  ///
  /// throws KeyNotFoundException if id does not exists
  ///
  /// [id] should not contains collectionName.
  Future<T?> getById(String id, {String sharedWith});

  /// deletes all the keys associated with [T.id]
  ///
  /// e.g alice's self key -
  /// ```
  /// 1234.collection@alice
  /// ```
  /// shared with bob -
  /// ```
  ///  @bob:1234.collection@alice
  /// ```
  ///
  /// both the keys will be deleted as they have the same ID (1234.collection)
  ///
  /// returns List<AtDataStatus>, where AtDataStatus represents delete status of individual keys.
  Future<List<AtDataStatus>> delete(T model);

  /// shares object [T] with [atSignsList].
  /// creates a new copy of data for every atSign in the list.
  ///
  /// if ```1234.collection@alice``` is being shared with @bob
  /// a new copy will be created as
  /// ```
  /// @bob:1234.collection@alice
  /// ```
  /// throws [exception] if [T.id] is empty.
  ///
  /// returns [AtShareOperation], which provides stream to listen for the status of share operation.
  ///
  /// e.g
  /// ```
  ///   var _newAtShareOperation = myModelAtCollectionImpl.share(data, ['@kevin', '@colin']);
  ///  _newAtShareOperation.atShareOperationStream.listen((atDataStatusEvent) {
  ///    /// current operation
  ///    print("${atDataStatusEvent.atSign}: ${atDataStatusEvent.status}");

  ///    /// to check if it is completed
  ///    if(_newAtShareOperation.atShareOperationStatus == AtShareOperationStatus.COMPLETE){
  ///      /// complete
  ///    }

  ///    /// all data till now
  ///    for(var _data in _newAtShareOperation.allData){
  ///      print("${_data.atSign}: ${_data.status}");
  ///    }
  ///  });
  ///
  ///  // to stop further shares
  ///  _newAtShareOperation.stop();
  /// ```
  AtShareOperation share(T model, List<String> atSignsList);

  /// If [T] is already with @alice, @bob, @john.
  ///
  /// unShare is used to delete the shared key for the atsigns in [atSignsList].
  ///
  /// If unshare is called on [T] with atSignsList as ```['@bob', '@john']```,
  /// It deletes shared keys for @bob and @john.
  ///
  /// For eg.
  /// ```
  /// var atUnshareOperation = data.unShare(['@sunglowgenerous', '@hacktheleague']);

  ///   atUnshareOperation.atUnshareOperationStream.listen((atDataStatusEvent) {
  ///     /// current operation
  ///     print("${atDataStatusEvent.atSign}: ${atDataStatusEvent.complete}");

  ///     /// to check if it is completed
  ///     if (atUnshareOperation.atUnshareOperationStatus ==
  ///         AtShareOperationStatus.COMPLETE) {
  ///       ///  completed
  ///     }

  ///     /// all data till now
  ///     for (var _data in atUnshareOperation.allData) {
  ///       print("${_data.atSign}: ${_data.complete}");
  ///     }
  ///   });
  ///
  ///  // to stop further unshares
  ///  atUnshareOperation.stop();
  /// ```
  AtUnshareOperation unShare(T model, List<String> atSignsList);

  /// returns List of atSign that the data [T] is shared with.
  ///
  /// If ```1234.collection@alice``` is shared with @bob and @john.
  /// It returns
  /// ```
  /// ['@bob', '@john']
  /// ```
  Future<List<String>> getSharedWithList(T model);
}
