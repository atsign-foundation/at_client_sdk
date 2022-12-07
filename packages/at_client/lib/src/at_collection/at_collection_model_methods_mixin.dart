import 'package:at_client/src/at_collection/at_collection_impl.dart';
import 'package:at_client/src/at_collection/model/at_collection_model.dart';
import 'package:at_client/src/at_collection/model/at_operation_item_status.dart';
import 'package:at_client/src/at_collection/model/at_share_operation.dart';
import 'package:at_client/src/at_collection/model/at_unshare_operation.dart';

/// [AtCollectionModelMethods] provides methods that can be performed on an object of [AtCollectionModel]
///
/// To use AtCollectionModelMethods methods extend your class with AtCollectionModelMethods
///
/// ```
/// class MyModel extends AtCollectionModel with AtCollectionModelMethods {}
/// ```
mixin AtCollectionModelMethods on AtCollectionModel {
  AtCollectionImpl? atCollectionImpl;

  init() {
    atCollectionImpl ??= AtCollectionImpl(
      collectionName: collectionName,
      convert: convert,
    );
  }

  /// Saves the object [T] in a self key.
  /// A unique id is generated and stored in [T.id].
  ///
  /// Returns true if operation was successful else returns false.
  ///
  /// [expiryTime] Represents the time in milliseconds beyond which the key expires.
  Future<bool> save({int? expiryTime}) async {
    init();
    return await atCollectionImpl!.save(this, expiryTime: expiryTime);
  }

  /// updates object [T] using [T.id] as identifier.
  /// Throws [Exception], if [T.id] or [T.collectionName] is empty.
  ///
  /// [update] also takes care of updating all the associated data with [T.id] if it has been shared with mutiple atSigns.
  ///
  /// returns List<AtOperationItemStatus>, where AtOperationItemStatus represents update status of individual keys.
  Future<List<AtOperationItemStatus>> update() async {
    init();
    return await atCollectionImpl!.update(this);
  }

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
  /// returns List<AtOperationItemStatus>, where AtOperationItemStatus represents delete status of individual keys.
  Future<List<AtOperationItemStatus>> delete() async {
    init();
    return await atCollectionImpl!.delete(this);
  }

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
  ///  _newAtShareOperation.atShareOperationStream.listen((AtOperationItemStatusEvent) {
  ///    /// current operation
  ///    print("${AtOperationItemStatusEvent.atSign}: ${AtOperationItemStatusEvent.status}");

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
  AtShareOperation share(List<String> atSignsList) {
    init();
    return atCollectionImpl!.share(this, atSignsList);
  }

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

  ///   atUnshareOperation.atUnshareOperationStream.listen((AtOperationItemStatusEvent) {
  ///     /// current operation
  ///     print("${AtOperationItemStatusEvent.atSign}: ${AtOperationItemStatusEvent.complete}");

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
  AtUnshareOperation unShare(List<String> atSignsList) {
    init();
    return atCollectionImpl!.unShare(this, atSignsList);
  }

  /// returns List of atSign that the data [T] is shared with.
  ///
  /// If ```1234.collection@alice``` is shared with @bob and @john.
  /// It returns
  /// ```
  /// ['@bob', '@john']
  /// ```
  Future<List<String>> getSharedWithList() async {
    init();
    return await atCollectionImpl!.getSharedWithList(this);
  }
}
