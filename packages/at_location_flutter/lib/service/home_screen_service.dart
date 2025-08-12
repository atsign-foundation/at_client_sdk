import 'package:at_location_flutter/location_modal/key_location_model.dart';
import 'package:at_location_flutter/location_modal/location_data_model.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/screens/map_screen/map_screen.dart';
import 'package:at_location_flutter/service/send_location_notification.dart';
import 'package:at_location_flutter/utils/constants/constants.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';
import 'package:flutter/material.dart';

import 'at_location_notification_listener.dart';
import 'master_location_service.dart';

class HomeScreenService {
  HomeScreenService._();

  static final HomeScreenService _instance = HomeScreenService._();

  factory HomeScreenService() => _instance;

  /// Handles the tap event on a location notification model
  void onLocationModelTap(
      LocationNotificationModel locationNotificationModel, bool haveResponded) {
    var currentAtsign = AtLocationNotificationListener().currentAtSign;

    if (locationNotificationModel.key!
        .contains(MixedConstants.SHARE_LOCATION)) {
      locationNotificationModel.atsignCreator != currentAtsign
          // ignore: unnecessary_statements
          ? (locationNotificationModel.isAccepted
              ? navigatorPushToMap(locationNotificationModel)
              : (locationNotificationModel.isExited
                  ? AtLocationNotificationListener().showMyDialog(
                      locationNotificationModel.atsignCreator,
                      locationNotificationModel)
                  : (haveResponded
                      ? null
                      : AtLocationNotificationListener().showMyDialog(
                          locationNotificationModel.atsignCreator,
                          locationNotificationModel))))
          : navigatorPushToMap(locationNotificationModel);
    } else if (locationNotificationModel.key!
        .contains(MixedConstants.REQUEST_LOCATION)) {
      var _creatorDetails = getCreatorDetails(locationNotificationModel);

      if (_creatorDetails == null) {
        return;
      }

      compareAtSign(locationNotificationModel.atsignCreator!, currentAtsign!)
          // ignore: unnecessary_statements
          ? (_creatorDetails.isAccepted
              ? navigatorPushToMap(locationNotificationModel)
              : (_creatorDetails.isExited
                  ? AtLocationNotificationListener().showMyDialog(
                      locationNotificationModel.atsignCreator,
                      locationNotificationModel)
                  : (haveResponded
                      ? null
                      : AtLocationNotificationListener().showMyDialog(
                          locationNotificationModel.atsignCreator,
                          locationNotificationModel))))
          // ignore: unnecessary_statements
          : (_creatorDetails.isAccepted
              ? navigatorPushToMap(locationNotificationModel)
              : null);
    }
  }

  /// Navigates to the MapScreen with the provided location notification model and current @sign
  void navigatorPushToMap(LocationNotificationModel locationNotificationModel) {
    Navigator.push(
      AtLocationNotificationListener().navKey.currentContext!,
      MaterialPageRoute(
          builder: (context) => MapScreen(
                currentAtSign: AtLocationNotificationListener().currentAtSign,
                userListenerKeyword: locationNotificationModel,
              )),
    );
  }
}

/// Returns the subtitle for a location notification model
String getSubTitle(LocationNotificationModel locationNotificationModel) {
  DateTime? to;
  String time;
  to = locationNotificationModel.to;
  if (to != null) {
    if (locationNotificationModel.to!.day > DateTime.now().day) {
      time =
          'until ${timeOfDayToString(TimeOfDay.fromDateTime(locationNotificationModel.to!))} tomorrow';
    } else {
      time =
          'until ${timeOfDayToString(TimeOfDay.fromDateTime(locationNotificationModel.to!))} today';
    }
  } else {
    time = '';
  }
  if (locationNotificationModel.key!.contains(MixedConstants.SHARE_LOCATION)) {
    return locationNotificationModel.atsignCreator ==
            AtLocationNotificationListener().currentAtSign
        ? 'Can see my location $time'
        : 'Can see their location $time';
  } else {
    // var _locationsharingFor =
    //     getLocationSharingForCreator(locationNotificationModel);

    // if ((_locationsharingFor != null) && (_locationsharingFor.to != null)) {
    //   time =
    //       'until ${timeOfDayToString(TimeOfDay.fromDateTime(_locationsharingFor.to!))} today';
    // } else {
    //   time = '';
    // }

    // return (_locationsharingFor != null && _locationsharingFor.isAccepted)
    //     ? (compareAtSign(locationNotificationModel.atsignCreator!,
    //             AtLocationNotificationListener().currentAtSign!)
    //         ? 'Sharing my location $time'
    //         : 'Sharing their location $time')
    //     : (compareAtSign(locationNotificationModel.atsignCreator!,
    //             AtLocationNotificationListener().currentAtSign!)
    //         ? 'Request Location received'
    //         : 'Request Location sent');

    ////////
    return locationNotificationModel.isAccepted
        ? (locationNotificationModel.atsignCreator ==
                AtLocationNotificationListener().currentAtSign
            ? 'Sharing my location $time'
            : 'Sharing their location $time')
        : (locationNotificationModel.atsignCreator ==
                AtLocationNotificationListener().currentAtSign
            ? 'Request Location received'
            : 'Request Location sent');
  }
}

/// Returns the semi-title for a location notification model
String? getSemiTitle(
    LocationNotificationModel locationNotificationModel, bool haveResponded) {
  if (locationNotificationModel.key!.contains(MixedConstants.SHARE_LOCATION)) {
    return locationNotificationModel.atsignCreator !=
            AtLocationNotificationListener().currentAtSign
        ? (locationNotificationModel.isAccepted
            ? null
            : locationNotificationModel.isExited
                ? 'Received Share location rejected'
                : (haveResponded ? 'Pending request' : 'Action required'))
        : (locationNotificationModel.isAccepted
            ? null
            : locationNotificationModel.isExited
                ? 'Sent Share location rejected'
                : 'Awaiting response');
  } else {
    var _memberInfo = getCreatorDetails(locationNotificationModel);

    if (_memberInfo == null) {
      return (locationNotificationModel.atsignCreator ==
              AtLocationNotificationListener().currentAtSign)
          ? 'Action required'
          : 'Awaiting response';
    }

    return locationNotificationModel.atsignCreator ==
            AtLocationNotificationListener().currentAtSign
        ? (!_memberInfo.isExited
            ? (_memberInfo.isAccepted
                ? null
                : (haveResponded ? 'Pending request' : 'Action required'))
            : 'Request rejected')
        : (!_memberInfo.isExited
            ? (_memberInfo.isAccepted ? null : 'Awaiting response')
            : 'Request rejected');
  }
}

/// Returns the creator details for a location notification model
LocationInfo? getCreatorDetails(
    LocationNotificationModel locationNotificationModel) {
  if (!compareAtSign(locationNotificationModel.atsignCreator!,
      AtLocationNotificationListener().currentAtSign!)) {
    return getOtherMemberLocationInfo(locationNotificationModel.key!,
        locationNotificationModel.atsignCreator!);
  }

  return getMyLocationInfo(locationNotificationModel);
}

/// Returns the location sharing information for the creator of a location notification model
LocationSharingFor? getLocationSharingForCreator(
    LocationNotificationModel locationNotificationModel) {
  var _atsignCreator = locationNotificationModel.atsignCreator!;
  var _id = trimAtsignsFromKey(locationNotificationModel.key!);

  if (!compareAtSign(locationNotificationModel.atsignCreator!,
      AtLocationNotificationListener().currentAtSign!)) {
    if ((MasterLocationService().locationReceivedData[_atsignCreator] !=
            null) &&
        (MasterLocationService()
                .locationReceivedData[locationNotificationModel.atsignCreator]!
                .locationSharingFor[_id] !=
            null)) {
      var _locationSharingFor = MasterLocationService()
          .locationReceivedData[_atsignCreator]!
          .locationSharingFor[_id]!;

      return _locationSharingFor;
    }
  } else {
    var _receiver = locationNotificationModel.receiver;
    if (SendLocationNotification().allAtsignsLocationData[_receiver] != null) {
      if (SendLocationNotification()
              .allAtsignsLocationData[_receiver]!
              .locationSharingFor[_id] !=
          null) {
        var _locationSharingFor = SendLocationNotification()
            .allAtsignsLocationData[_receiver]!
            .locationSharingFor[_id]!;

        return _locationSharingFor;
      }
    }
  }
  return null;
}

/// Returns the title for a location notification model
String? getTitle(LocationNotificationModel locationNotificationModel) {
  if (locationNotificationModel.key!.contains(MixedConstants.SHARE_LOCATION)) {
    return locationNotificationModel.atsignCreator ==
            AtLocationNotificationListener().currentAtSign
        ? locationNotificationModel.receiver
        : locationNotificationModel.atsignCreator;
  } else {
    return locationNotificationModel.atsignCreator ==
            AtLocationNotificationListener().currentAtSign
        ? locationNotificationModel.receiver
        : locationNotificationModel.atsignCreator;
  }
}

/// Determines whether to show the retry option for a location notification
bool calculateShowRetry(KeyLocationModel keyLocationModel) {
  if (keyLocationModel.locationNotificationModel!.key!
      .contains('sharelocation')) {
    if ((keyLocationModel.locationNotificationModel!.atsignCreator !=
            AtLocationNotificationListener().currentAtSign) &&
        (!keyLocationModel.locationNotificationModel!.isAccepted) &&
        (!keyLocationModel.locationNotificationModel!.isExited) &&
        (keyLocationModel.haveResponded!)) return true;

    return false;
  } else {
    if ((keyLocationModel.locationNotificationModel!.atsignCreator ==
            AtLocationNotificationListener().currentAtSign) &&
        (!keyLocationModel.locationNotificationModel!.isAccepted) &&
        (!keyLocationModel.locationNotificationModel!.isExited) &&
        (keyLocationModel.haveResponded!)) return true;

    return false;
  }
}

/// Converts a [TimeOfDay] object to a formatted string representation
String timeOfDayToString(TimeOfDay time) {
  var minute = time.minute;
  if (minute < 10) return '${time.hour}: 0${time.minute}';

  return '${time.hour}: ${time.minute}';
}
