import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_location_flutter/location_modal/key_location_model.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/service/key_stream_service.dart';
import 'package:at_location_flutter/service/master_location_service.dart';
import 'package:at_location_flutter/service/notify_and_put.dart';
import 'package:at_location_flutter/service/request_location_service.dart';
import 'package:at_location_flutter/service/send_location_notification.dart';
import 'package:at_location_flutter/service/sharing_location_service.dart';
import 'package:at_location_flutter/utils/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:at_utils/at_logger.dart';

/// Function to initialise the package. Should be mandatorily called before accessing package functionalities.
///
/// [mapKey] is needed to access maps.
///
/// [apiKey] is needed to calculate ETA.
///
/// Steps to get [mapKey]/[apiKey] available in README.
///
/// [showDialogBox] if false dialog box wont be shown.
///
/// [streamAlternative] a function which will return updated lists of [KeyLocationModel].
///
/// [isEventInUse] to signify if the events package is used.
Future<void> initializeLocationService(GlobalKey<NavigatorState> navKey,
    {required String mapKey,
    required String apiKey,
    bool showDialogBox = false,
    String rootDomain = 'root.atsign.org',
    Function? getAtValue,
    Function(List<KeyLocationModel>)? streamAlternative,
    bool isEventInUse = false}) async {
  final _logger = AtSignLogger('initializeLocationService');

  /// initialise keys
  MixedConstants.setApiKey(apiKey);
  MixedConstants.setMapKey(mapKey);

  try {
    /// So that we have the permission status beforehand & later we dont get
    /// PlatformException(PermissionHandler.PermissionManager) => Multiple Permissions exception
    await Geolocator.requestPermission();
  } catch (e) {
    _logger.severe('Error in requesting location permission: $e');
  }

  /// first get all location-notify keys, mine and others
  SendLocationNotification().reset();
  await SendLocationNotification().getAllLocationShareKeys();
  await MasterLocationService().init(
      AtClientManager.getInstance().atClient.getCurrentAtSign()!,
      AtClientManager.getInstance().atClient,
      newGetAtValueFromMainApp: getAtValue);

  AtLocationNotificationListener().init(navKey, rootDomain, showDialogBox,
      newGetAtValueFromMainApp: getAtValue, isEventInUse: isEventInUse);
  KeyStreamService().init(AtLocationNotificationListener().atClientInstance,
      streamAlternative: streamAlternative);
}

/// returns a Stream of 'KeyLocationModel' having all the shared and request location keys.
Stream getAllNotification() {
  return KeyStreamService().atNotificationsStream;
}

/// sends a share location notification to the [atsign], with a 'ttl' of [minutes].
/// before calling this [atsign] should be checked if valid or not.
Future<bool?> sendShareLocationNotification(String atsign, int? minutes) async {
  var result = await SharingLocationService()
      .sendShareLocationEvent(atsign, false, minutes: minutes);
  return result;
}

/// sends a request location notification to the [atsign].
/// before calling this [atsign] should be checked if valid or not.
Future<bool?> sendRequestLocationNotification(String atsign) async {
  var result = await RequestLocationService().sendRequestLocationEvent(atsign);
  return result;
}

/// deletes the location notification of the logged in atsign being shared with [locationNotificationModel].receiver
Future<bool> deleteLocationData(
    LocationNotificationModel locationNotificationModel) async {
  // ignore: todo
  // TODO: verify receiver
  var result = await SendLocationNotification()
      .sendNull([locationNotificationModel.receiver!]);
  return result;
}

/// deletes all the location notifications of the logged in atsign being shared with any atsign
void deleteAllLocationData() {
  SendLocationNotification().deleteAllLocationKey();
}

/// returns the 'AtKey' of the [regexKey]
AtKey getAtKey(String regexKey) {
  var atKey = AtKey.fromString(regexKey);
  atKey.metadata.ttr = -1;
  atKey.metadata.ccd = true;
  return atKey;
}

/// returns true if [atsign1] & [atsign2] are same
bool compareAtSign(String atsign1, String atsign2) {
  if (atsign1[0] != '@') {
    atsign1 = '@$atsign1';
  }
  if (atsign2[0] != '@') {
    atsign2 = '@$atsign2';
  }

  return atsign1.toLowerCase() == atsign2.toLowerCase() ? true : false;
}

/// input => '@25antwilling:sharelocation-1637156978786327@26juststay' or 'sharelocation-1637156978786327'
/// output => sharelocation-1637156978786327
String trimAtsignsFromKey(String key) {
  key = NotifyAndPut().removeNamespaceFromString(key);

  key = key.replaceAll('cached:', '');

  if (key.contains(':')) {
    key = key.split(':')[1];
  }
  if (key.contains('@')) {
    key = key.split('@')[0];
  }
  return key;
}

/// will return details of my booleans for this [LocationNotificationModel]
LocationInfo? getMyLocationInfo(LocationNotificationModel _event) {
  String _id = trimAtsignsFromKey(_event.key!);

  if (!compareAtSign(_event.atsignCreator!,
      AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
    return null;
  }

  if (SendLocationNotification().allAtsignsLocationData[_event.receiver] !=
      null) {
    if (SendLocationNotification()
            .allAtsignsLocationData[_event.receiver]!
            .locationSharingFor[_id] !=
        null) {
      var _locationSharingFor = SendLocationNotification()
          .allAtsignsLocationData[_event.receiver]!
          .locationSharingFor[_id]!;

      return LocationInfo(
          isSharing: _locationSharingFor.isSharing,
          isExited: _locationSharingFor.isExited,
          isAccepted: _locationSharingFor.isAccepted);
    }
  }
  return null;
}

/// will return details of others booleans for this [LocationNotificationModel]
LocationInfo? getOtherMemberLocationInfo(String _id, String _atsign) {
  _id = trimAtsignsFromKey(_id);

  // for (var key in MasterLocationService().locationReceivedData.entries) {
  if ((MasterLocationService().locationReceivedData[_atsign] != null) &&
      (MasterLocationService()
              .locationReceivedData[_atsign]!
              .locationSharingFor[_id] !=
          null)) {
    var _locationSharingFor = MasterLocationService()
        .locationReceivedData[_atsign]!
        .locationSharingFor[_id]!;

    return LocationInfo(
        isSharing: _locationSharingFor.isSharing,
        isExited: _locationSharingFor.isExited,
        isAccepted: _locationSharingFor.isAccepted);
  }
  return null;
  // }
}
