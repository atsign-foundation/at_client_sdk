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
