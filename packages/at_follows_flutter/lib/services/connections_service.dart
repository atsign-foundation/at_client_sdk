import 'package:at_client/at_client.dart' hide Atsign;
import 'package:at_client_mobile/at_client_mobile.dart' hide Atsign;
import 'package:at_follows_flutter/domain/at_follows_list.dart';
import 'package:at_follows_flutter/domain/atsign.dart';
import 'package:at_follows_flutter/domain/connection_model.dart';
import 'package:at_follows_flutter/services/sdk_service.dart';
import 'package:at_follows_flutter/utils/app_constants.dart';
import 'package:at_follows_flutter/utils/strings.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client_mobile/at_client_mobile.dart' hide Atsign;
import 'package:at_client/at_client.dart' hide Atsign;

import 'notification_service.dart' as follows_notification_service;

class ConnectionsService {
  static final ConnectionsService _singleton = ConnectionsService._internal();

  late AtFollowsList followers;
  late AtFollowsList following;
  String? followerAtsign;
  String? followAtsign;
  String initialised = '';

  var _logger = AtSignLogger('Connections Service');

  SDKService _sdkService = SDKService();

  ConnectionsService._internal();

  factory ConnectionsService() {
    return _singleton;
  }

  var connectionProvider = ConnectionProvider();

  late bool isMonitorStarted;

  init(String atsign) {
    if (atsign != initialised) {
      followers = AtFollowsList();
      following = AtFollowsList();
      isMonitorStarted = false;
      initialised = atsign;
    }
  }

  // method to get atsign list
  Future<void> getAtsignsList({bool isInit = false}) async {
    if (connectionProvider.followingList!.isEmpty || isInit) {
      await createLists(isFollowing: true);
      if (following.list!.isNotEmpty) {
        connectionProvider.followingList = await _formAtSignData(following.list!, isFollowing: true);
      }
      await _sdkService.sync();
      if (!this.following.contains(this.followAtsign) && this.followAtsign != null) {
        var atsignData = await this.follow(this.followAtsign);
        if (atsignData != null) {
          connectionProvider.followingList!.add(atsignData);
        }
        this.followAtsign = null;
      }
    }
    await _sdkService.sync();
    if (connectionProvider.followersList!.isEmpty || isInit) {
      await createLists(isFollowing: false);
      if (followers.list!.isNotEmpty) {
        connectionProvider.followersList = await _formAtSignData(followers.list!);
      }
    }
    if (isInit) {
      var fromDate = followers.getKey != null ? followers.getKey!.metadata?.updatedAt : null;
      var notificationsList = await _sdkService.notifyList(fromDate: fromDate?.toString());
      //filtering notifications which has only new followers
      for (var notification in notificationsList) {
        if (notification.operation == Operation.update) {
          await this.updateFollowers(notification, isSetStatus: false);
        } else if (notification.operation == Operation.delete &&
            notification.key.contains(AppConstants.containsFollowing)) {
          await this.deleteFollowers(notification, isSetStatus: false);
        } else if (notification.operation == Operation.delete &&
            notification.key.contains(AppConstants.containsFollowers)) {
          await this.deleteFollowing(notification, isSetStatus: false);
        }
      }
      await _sdkService.sync();
    }
  }

  Future<List<Atsign>> _formAtSignData(List<String?> connectionsList, {bool isFollowing = false}) async {
    List<Atsign> atsignList = [];
    for (var connection in connectionsList) {
      var atsignData = await _getAtsignData(connection, isFollowing: isFollowing);
      atsignList.add(atsignData);
    }
    atsignList.sort((a, b) => a.title![1].compareTo(b.title![1]));
    return atsignList;
  }

  ///Follows an [atsign] by adding it in your followers list
  Future<Atsign?> follow(String? atsign) async {
    if (atsign == _sdkService.atsign) {
      return null;
    }
    atsign = formatAtSign(atsign);
    var atKey = this._formKey(isFollowing: true);
    var atMetadata = atKey.metadata;
    if (following.list!.contains(atsign) || atsign == _sdkService.atsign) {
      return null;
    }
    following.add(atsign);
    var result = await _sdkService.put(atKey, following.toString());
    await _sdkService.sync();
    //change metadata to private to notify
    if (result) {
      atKey..sharedWith = atsign;
      atMetadata..isPublic = false;
      atKey..metadata = atMetadata;
      await _sdkService.notify(atKey, atsign!, OperationEnum.update, _onNotifyDone, _onNotifyError);
    }
    var atsignData = await _getAtsignData(atsign, isNew: true, isFollowing: true);
    await _sdkService.sync();
    return atsignData;
  }

  ///Deletes the [atsign] from followers and following lists.
  Future<bool> delete(String atsign) async {
    bool result;

    //deleting @sign from followers
    var atKey = this._formKey();
    var atMetadata = atKey.metadata;
    result = await _modifyKey(atsign, followers, atKey);
    //notify @sign about delete
    if (result) {
      atKey..sharedWith = atsign;
      atMetadata..isPublic = false;
      atKey..metadata = atMetadata;
      await _sdkService.notify(atKey, atsign, OperationEnum.delete, _onNotifyDone, _onNotifyError);
    }

    //deleting @sign from following
    atKey = this._formKey(isFollowing: true);
    atMetadata = atKey.metadata;
    result = await _modifyKey(atsign, following, atKey);
    //notify @sign about delete
    if (result) {
      atKey..sharedWith = atsign;
      atMetadata..isPublic = false;
      atKey..metadata = atMetadata;
      await _sdkService.notify(atKey, atsign, OperationEnum.delete, _onNotifyDone, _onNotifyError);
    }

    await _sdkService.sync();
    return result;
  }

  // method to unfollow an atsign
  Future<bool> unfollow(String? atsign) async {
    atsign = formatAtSign(atsign);
    var atKey = this._formKey(isFollowing: true);
    var atMetadata = atKey.metadata;
    var result = await _modifyKey(atsign, this.following, atKey);
    if (result) {
      atKey..sharedWith = atsign;
      atMetadata..isPublic = false;
      atKey..metadata = atMetadata;
      await _sdkService.notify(atKey, atsign!, OperationEnum.delete, _onNotifyDone, _onNotifyError);
      await _sdkService.sync();
    }
    return result;
  }

  // method to remove follower in list
  Future<bool> removeFollower(String atsign) async {
    var followersList = followers.getKey!.value.split(',');
    bool result = false;
    var atKey = _formKey();
    followersList.remove(atsign);
    if (followersList.isNotEmpty) {
      result = await _sdkService.put(atKey, followersList.toString());
      followers.list!.remove(atsign);
    } else {
      result = await _sdkService.put(atKey, 'null');
    }
    return result;
  }

  Future<bool> _modifyKey(String? atsign, AtFollowsList atFollowsList, AtKey atKey) async {
    var result = false;
    if (!atFollowsList.list!.contains(atsign) || atsign == _sdkService.atsign) {
      return false;
    }
    atFollowsList.remove(atsign);
    if (atFollowsList.toString().isEmpty) {
      result = await _sdkService.put(atKey, 'null');
    } else {
      result = await _sdkService.put(atKey, atFollowsList.toString());
    }
    await _sdkService.sync();
    return result;
  }

  ///Returns `true` on changing the status of the list to [isPrivate].
  Future<bool> changeListPublicStatus(bool isFollowing, bool isPrivate) async {
    isFollowing ? following.isPrivate = isPrivate : followers.isPrivate = isPrivate;
    var atFollowsValue = AtFollowsValue()..atKey = _formKey(isFollowing: isFollowing);
    bool result = await this._sdkService.delete(isFollowing ? following.getKey!.atKey : followers.getKey!.atKey);
    isFollowing ? following.setKey = atFollowsValue : followers.setKey = atFollowsValue;
    String value = isFollowing ? following.toString() : followers.toString();
    result = await this._sdkService.put(atFollowsValue.atKey, value);
    await _sdkService.sync();
    return result;
  }

  ///adds [notification.fromAtSign] into followers list.
  Future<void> updateFollowers(AtNotification notification, {bool isSetStatus = true}) async {
    try {
      if (isSetStatus) connectionProvider.setStatus(Status.loading);
      var atKey = this._formKey();
      if (followers.list!.contains(notification.from)) {
        if (isSetStatus) connectionProvider.setStatus(Status.done);
        return;
      }
      followers.add(notification.from);
      await _sdkService.put(atKey, followers.toString());
      await _sdkService.sync();
      var atsignData = await _getAtsignData(
        notification.from,
        isNew: true,
      );
      connectionProvider.followersList!.add(atsignData);
      if (isSetStatus) {
        connectionProvider.setStatus(Status.done);
        await _sdkService.sync();
      }
    } catch (err) {
      connectionProvider.error = err;
      connectionProvider.setStatus(Status.error);
    }
  }

  ///deletes [notification.fromAtSign] from followers list.
  Future<void> deleteFollowers(AtNotification notification, {bool isSetStatus = true}) async {
    try {
      if (isSetStatus) connectionProvider.setStatus(Status.loading);
      if (!followers.list!.contains(notification.from)) {
        if (isSetStatus) connectionProvider.setStatus(Status.done);
        return;
      }
      followers.remove(notification.from);
      var atKey = this._formKey();
      followers.list!.isNotEmpty
          ? await _sdkService.put(atKey, followers.toString())
          : await this._sdkService.put(atKey, 'null');

      connectionProvider.followersList!.removeWhere((element) => element.title == notification.from);
      if (isSetStatus) {
        connectionProvider.setStatus(Status.done);
        await _sdkService.sync();
      }
    } catch (err) {
      connectionProvider.error = err;
      connectionProvider.setStatus(Status.error);
    }
  }

  ///deletes [notification.fromAtSign] from following list.
  Future<void> deleteFollowing(AtNotification notification, {bool isSetStatus = true}) async {
    try {
      if (isSetStatus) connectionProvider.setStatus(Status.loading);
      if (!following.list!.contains(notification.from)) {
        if (isSetStatus) connectionProvider.setStatus(Status.done);
        return;
      }
      following.remove(notification.from);
      var atKey = this._formKey(isFollowing: true);
      following.list!.isNotEmpty
          ? await _sdkService.put(atKey, following.toString())
          : await this._sdkService.put(atKey, 'null');

      connectionProvider.followingList!.removeWhere((element) => element.title == notification.from);
      if (isSetStatus) {
        connectionProvider.setStatus(Status.done);
        await _sdkService.sync();
      }
    } catch (err) {
      connectionProvider.error = err;
      connectionProvider.setStatus(Status.error);
    }
  }

  ///creates following and followers list.
  Future<void> createLists({required bool isFollowing}) async {
    // for following list followers list is not required.
    if (!isFollowing) {
      var followersValue = await _sdkService.scanAndGet(AppConstants.followersKey);
      this.followers.create(followersValue);
      if (followersValue.metadata != null) {
        connectionProvider.connectionslistStatus.isFollowersPrivate = !followersValue.metadata!.isPublic;
        await _sdkService.sync();
      }
    } else {
      // for followers list following list is required to show the status of follow button.

      var followingValue = await _sdkService.scanAndGet(AppConstants.followingKey);
      this.following.create(followingValue);

      if (followingValue.metadata != null) {
        connectionProvider.connectionslistStatus.isFollowingPrivate = !followingValue.metadata!.isPublic;
        await _sdkService.sync();
      }
    }
  }

  void _onNotifyDone(String notifyResult) {
    _logger.finer('notification complete $notifyResult');
  }

  void _onNotifyError(var error) {
    _logger.finer('notification error ${error.toString()}');
  }

  AtKey _formKey({bool isFollowing = false, String? atsign}) {
    var atKey;
    var atSign = atsign ?? _sdkService.atsign;
    if (isFollowing) {
      var atMetadata = Metadata()..isPublic = !following.isPrivate;
      atKey = AtKey()
        ..metadata = atMetadata
        ..key = AppConstants.followingKey
        ..sharedWith = atMetadata.isPublic ? null : atSign;
    } else {
      var atMetadata = Metadata()..isPublic = !followers.isPrivate;
      atKey = AtKey()
        ..metadata = atMetadata
        ..key = AppConstants.followersKey
        ..sharedWith = atMetadata.isPublic ? null : atSign;
    }
    return atKey;
  }

  // method to get atsign data
  Future<Atsign> _getAtsignData(String? connection, {bool isFollowing = true, bool isNew = false}) async {
    AtKey atKey;
    Atsign atsignData = Atsign()
      ..title = connection
      ..isFollowing = following.list!.contains(connection);
    try {
      var data = connectionProvider.getData(!isFollowing, connection);
      if (data != null) {
        return data;
      }
      atKey = AtKey()..sharedBy = connection;
      AtFollowsValue atValue = AtFollowsValue();
      for (var key in PublicData.list) {
        /// if fetching one key fails, should not effect other keys
        try {
          atKey..metadata = _getPublicFieldsMetadata(key);
          atKey..key = key;
          atKey..sharedWith = null;
          atValue = await _sdkService.get(atKey);
          //performs plookup if the data is not in cache.
          if (atValue.value == null) {
            //plookup for wavi keys.
            atKey.metadata.isCached = false;

            /// remove cached
            key.replaceAll('cached:', '');
            atKey.key.replaceAll('cached:', '');
            atValue = await _sdkService.get(atKey);
            //cache lookup for persona keys
            if (atValue.value == null) {
              atKey.key = PublicData.personaMap[key] ?? "";
              atKey.metadata.isCached = true;
              atValue = await _sdkService.get(atKey);
              //plookup for persona keys.
              if (atValue.value == null) {
                atKey.metadata.isCached = false;
                atValue = await _sdkService.get(atKey);
              }
            }
          }

          atsignData.setData(atValue);
        } catch (e) {
          _logger.severe('Error in _getAtsignData getting value $e');
        }
      }
    } catch (e) {
      _logger.severe('Fetching keys for $connection throws $e');
    }

    return atsignData;
  }

  _getPublicFieldsMetadata(String key) {
    var atmetadata = Metadata()
      ..namespaceAware = false

      /// if cached
      ..isCached = key.contains('cached')
      ..isBinary = key == PublicData.image || key == PublicData.imagePersona
      ..isPublic = true;
    return atmetadata;
  }

  ///Returns null if [atsign] is null else the formatted [atsign].
  ///[atsign] must be non-null.
  String? formatAtSign(String? atsign) {
    if (atsign == null) {
      return null;
    } else if (atsign.contains(':')) {
      return Strings.invalidAtsign;
    }
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    atsign = !atsign.startsWith('@') ? '@' + atsign : atsign;
    return atsign;
  }

  bool startMonitor() {
    AtClientManager.getInstance().atClient.notificationService.subscribe().listen((notification) {
      acceptStream(notification);
    });
    isMonitorStarted = true;
    return true;
  }

  acceptStream(AtNotification notification) async {
    _logger.info(
        'Received notification:: id:${notification.id} key:${notification.key} operation:${notification.operation} from:${notification.from} to:${notification.to}');
    if (notification.operation == Operation.update &&
        notification.to == _sdkService.atsign &&
        notification.key.contains(AppConstants.containsFollowing)) {
      await updateFollowers(notification);
      await follows_notification_service.NotificationService().showNotification(notification);
    } else if (notification.operation == Operation.delete &&
        notification.to == _sdkService.atsign &&
        notification.key.contains(AppConstants.containsFollowing)) {
      await deleteFollowers(notification);
    } else if (notification.operation == Operation.delete &&
        notification.to == _sdkService.atsign &&
        notification.key.contains(AppConstants.containsFollowers)) {
      await deleteFollowing(notification);
    }
  }
}

class AtFollowsValue extends AtValue {
  late AtKey atKey;
}

class Operation {
  static final String update = 'update';
  static final String delete = 'delete';
}
