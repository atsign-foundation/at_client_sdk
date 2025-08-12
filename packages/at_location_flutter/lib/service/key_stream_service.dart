import 'dart:async';
import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_location_flutter/location_modal/key_location_model.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/service/request_location_service.dart';
import 'package:at_location_flutter/utils/constants/constants.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';

import 'contact_service.dart';
import 'send_location_notification.dart';
import 'package:at_utils/at_logger.dart';

class KeyStreamService {
  KeyStreamService._();

  static final KeyStreamService _instance = KeyStreamService._();

  factory KeyStreamService() => _instance;

  final _logger = AtSignLogger('KeyStreamService');

  AtClient? atClientInstance;
  AtContactsImpl? atContactImpl;
  AtContact? loggedInUserDetails;
  List<KeyLocationModel> allLocationNotifications = [];
  String? currentAtSign;
  List<AtContact> contactList = [];

  // ignore: close_sinks
  StreamController atNotificationsController =
      StreamController<List<KeyLocationModel>>.broadcast();

  Stream<List<KeyLocationModel>> get atNotificationsStream =>
      atNotificationsController.stream as Stream<List<KeyLocationModel>>;

  StreamSink<List<KeyLocationModel>> get atNotificationsSink =>
      atNotificationsController.sink as StreamSink<List<KeyLocationModel>>;

  Function(List<KeyLocationModel>)? streamAlternative;

  void init(AtClient? clientInstance,
      {Function(List<KeyLocationModel>)? streamAlternative}) async {
    loggedInUserDetails = null;
    atClientInstance = clientInstance;
    currentAtSign = atClientInstance!.getCurrentAtSign();
    allLocationNotifications = [];
    this.streamAlternative = streamAlternative;

    atNotificationsController =
        StreamController<List<KeyLocationModel>>.broadcast();
    getAllNotifications();

    loggedInUserDetails = await getAtSignDetails(currentAtSign);
    getAllContactDetails(currentAtSign!);
  }

  void getAllContactDetails(String currentAtSign) async {
    atContactImpl = await AtContactsImpl.getInstance(currentAtSign);
    contactList = await atContactImpl!.listContacts();
  }

  /// adds all share and request location notifications to [atNotificationsSink]
  void getAllNotifications() async {
    AtClientManager.getInstance().atClient.syncService.sync();

    var allResponse = await atClientInstance!.getKeys(
      regex: 'sharelocation-',
    );

    var allRequestResponse = await atClientInstance!.getKeys(
      regex: 'requestlocation-',
    );

    allResponse = [...allResponse, ...allRequestResponse];

    if (allResponse.isEmpty) {
      SendLocationNotification().init(atClientInstance);
      notifyListeners();
      return;
    }

    await Future.forEach(allResponse, (String key) async {
      var _atKey = getAtKey(key);
      AtValue? value = await getAtValue(_atKey);
      if (value != null) {
        try {
          if ((value.value != null) && (value.value != 'null')) {
            var locationNotificationModel =
                LocationNotificationModel.fromJson(jsonDecode(value.value));
            allLocationNotifications.insert(
                0,
                KeyLocationModel(
                    locationNotificationModel:
                        locationNotificationModel)); // last item to come in would be at the top of the list
          }
        } catch (e) {
          _logger.severe('convertJsonToLocationModel error :$e');
        }
      }
    });

    filterData();
    await checkForPendingLocations();
    notifyListeners();

    SendLocationNotification().init(atClientInstance);
  }

  /// Updates any received notification with [haveResponded] true, if already responded.
  Future<void> checkForPendingLocations() async {
    await Future.forEach(allLocationNotifications,
        (KeyLocationModel notification) async {
      if (notification.locationNotificationModel!.key!
          .contains(MixedConstants.SHARE_LOCATION)) {
        if ((notification.locationNotificationModel!.atsignCreator !=
                currentAtSign) &&
            (!notification.locationNotificationModel!.isAccepted) &&
            (!notification.locationNotificationModel!.isExited)) {
          var atkeyMicrosecondId = notification.locationNotificationModel!.key!
              .split('sharelocation-')[1]
              .split('@')[0];
          var acknowledgedKeyId =
              'sharelocationacknowledged-$atkeyMicrosecondId';
          var allRegexResponses =
              await atClientInstance!.getKeys(regex: acknowledgedKeyId);
          // ignore: unnecessary_null_comparison
          if ((allRegexResponses != null) && (allRegexResponses.isNotEmpty)) {
            notification.haveResponded = true;
          }
        }
      }

      if (notification.locationNotificationModel!.key!
          .contains(MixedConstants.REQUEST_LOCATION)) {
        if ((notification.locationNotificationModel!.atsignCreator ==
                currentAtSign) &&
            (!notification.locationNotificationModel!.isAccepted) &&
            (!notification.locationNotificationModel!.isExited)) {
          var atkeyMicrosecondId = notification.locationNotificationModel!.key!
              .split('requestlocation-')[1]
              .split('@')[0];
          var acknowledgedKeyId =
              'requestlocationacknowledged-$atkeyMicrosecondId';
          var allRegexResponses =
              await atClientInstance!.getKeys(regex: acknowledgedKeyId);
          // ignore: unnecessary_null_comparison
          if ((allRegexResponses != null) && (allRegexResponses.isNotEmpty)) {
            notification.haveResponded = true;
          }
        }
      }
    });
  }

  /// Updates the pending status of a location notification
  void updatePendingStatus(LocationNotificationModel notification) {
    for (var i = 0; i < allLocationNotifications.length; i++) {
      if ((allLocationNotifications[i]
          .locationNotificationModel!
          .key!
          .contains(notification.key!))) {
        allLocationNotifications[i].haveResponded = true;
        break;
      }
    }
    notifyListeners();
  }

  /// Checks for missed 'Remove Person' requests for request location notifications
  void checkForDeleteRequestAck() async {
    // Letting other events complete
    await Future.delayed(const Duration(seconds: 5));

    var dltRequestLocationResponse = await atClientInstance!.getKeys(
      regex: 'deleterequestacklocation',
    );

    for (var i = 0; i < dltRequestLocationResponse.length; i++) {
      /// Operate on receied notifications
      if (dltRequestLocationResponse[i].contains('cached')) {
        var atkeyMicrosecondId = dltRequestLocationResponse[i]
            .split('deleterequestacklocation-')[1]
            .split('@')[0];

        var _index = allLocationNotifications.indexWhere((element) {
          return (element.locationNotificationModel!.key!
                  .contains(atkeyMicrosecondId) &&
              (element.locationNotificationModel!.key!
                  .contains(MixedConstants.SHARE_LOCATION)));
        });

        if (_index == -1) continue;

        await RequestLocationService().deleteKey(
            allLocationNotifications[_index].locationNotificationModel!);
      }
    }
  }

  /// Removes past notifications and notification where data is null.
  void filterData() {
    var tempArray = <KeyLocationModel>[];
    for (var i = 0; i < allLocationNotifications.length; i++) {
      // ignore: unrelated_type_equality_checks
      if ((allLocationNotifications[i].locationNotificationModel == 'null') ||
          (allLocationNotifications[i].locationNotificationModel == null)) {
        tempArray.add(allLocationNotifications[i]);
      } else {
        if ((allLocationNotifications[i].locationNotificationModel!.to !=
                null) &&
            (allLocationNotifications[i]
                    .locationNotificationModel!
                    .to!
                    .difference(DateTime.now())
                    .inMinutes <
                0)) tempArray.add(allLocationNotifications[i]);
      }
    }
    allLocationNotifications
        .removeWhere((element) => tempArray.contains(element));
  }

  /// Updates any [KeyLocationModel] data for updated data
  Future<void> mapUpdatedLocationDataToWidget(
      LocationNotificationModel locationData,
      {bool shouldCheckForTimeChanges = false}) async {
    /// so, that we don't add any expired event
    if (isPastNotification(locationData)) {
      return;
    }

    String newLocationDataKeyId;
    if (locationData.key!.contains(MixedConstants.SHARE_LOCATION)) {
      newLocationDataKeyId =
          locationData.key!.split('sharelocation-')[1].split('@')[0];
    } else {
      newLocationDataKeyId =
          locationData.key!.split('requestlocation-')[1].split('@')[0];
    }

    //// If we want to add any such notification that is not in the list, but we get an update
    var _locationDataNotPresent = true;

    for (var i = 0; i < allLocationNotifications.length; i++) {
      if (allLocationNotifications[i]
          .locationNotificationModel!
          .key!
          .contains(newLocationDataKeyId)) {
        allLocationNotifications[i].locationNotificationModel = locationData;
        _locationDataNotPresent = false;
      }
    }

    if (_locationDataNotPresent) {
      addDataToList(locationData);
    }
    notifyListeners();

    if (shouldCheckForTimeChanges) {
      SendLocationNotification()
          .allAtsignsLocationData[locationData.receiver!]!
          .locationSharingFor[trimAtsignsFromKey(locationData.key!)]!
          .from = locationData.from;

      SendLocationNotification()
          .allAtsignsLocationData[locationData.receiver!]!
          .locationSharingFor[trimAtsignsFromKey(locationData.key!)]!
          .to = locationData.to;

      SendLocationNotification()
          .sendLocationAfterDataUpdate([locationData.receiver!]);

      return;
    }

    // Update location sharing
    if ((locationData.isSharing) && (locationData.isAccepted)) {
      if (locationData.atsignCreator == currentAtSign) {
        var _tempLocationDataModel = SendLocationNotification()
            .locationNotificationModelToLocationDataModel(locationData);

        if (SendLocationNotification()
            .ifLocationDataAlreadyExists(_tempLocationDataModel)) {
          SendLocationNotification()
              .allAtsignsLocationData[locationData.receiver!]!
              .locationSharingFor = {
            ...SendLocationNotification()
                .allAtsignsLocationData[locationData.receiver!]!
                .locationSharingFor,
            ..._tempLocationDataModel.locationSharingFor,
          };

          SendLocationNotification()
              .sendLocationAfterDataUpdate([locationData.receiver!]);
        } else {
          SendLocationNotification().addMember(_tempLocationDataModel);
        }
      }
    } else {
      if (compareAtSign(locationData.atsignCreator!, currentAtSign!)) {
        //// ifLocationDataAlreadyExists remove
        SendLocationNotification().removeMember(
            locationData.key!, [locationData.receiver!],
            isExited: locationData.isExited,
            isAccepted: locationData.isAccepted,
            isSharing: locationData.isSharing);
        //// Else add it
      }
    }
  }

  /// Removes a notification from list
  void removeData(String? key) {
    /// received key Example:
    ///  key: sharelocation-1637059616606602@26juststay
    ///
    if (key == null) {
      return;
    }

    LocationNotificationModel? locationNotificationModel;

    String atsignToDelete = '';
    allLocationNotifications.removeWhere((notification) {
      if (key.contains(
          trimAtsignsFromKey(notification.locationNotificationModel!.key!))) {
        atsignToDelete = notification.locationNotificationModel!.receiver!;
        locationNotificationModel = notification.locationNotificationModel;
      }
      return key.contains(
          trimAtsignsFromKey(notification.locationNotificationModel!.key!));
    });
    notifyListeners();
    // Remove location sharing
    if (locationNotificationModel != null)
    // && (compareAtSign(locationNotificationModel.atsignCreator!, currentAtSign!))
    {
      SendLocationNotification().removeMember(key, [atsignToDelete],
          isExited: true, isAccepted: false, isSharing: false);
    }
  }

  /// Checks if a location notification is in the past
  isPastNotification(LocationNotificationModel _locationNotificationModel) {
    if ((_locationNotificationModel.to != null) &&
        (_locationNotificationModel.to!.isBefore(DateTime.now()))) {
      return true;
    }
    return false;
  }

  /// Adds new [KeyLocationModel] data for new received notification
  Future<dynamic> addDataToList(
      LocationNotificationModel locationNotificationModel,
      {String? receivedkey}) async {
    /// so, that we don't add any expired event
    if (isPastNotification(locationNotificationModel)) {
      return;
    }

    /// with rSDK we can get previous notification, this will restrict us to add one notification twice
    for (var _locationNotification in allLocationNotifications) {
      if (_locationNotification.locationNotificationModel!.key ==
          locationNotificationModel.key) {
        return;
      }
    }

    var tempHyridNotificationModel = KeyLocationModel();
    tempHyridNotificationModel.locationNotificationModel =
        locationNotificationModel;
    allLocationNotifications.insert(0,
        tempHyridNotificationModel); // last item to come in would be at the top of the list

    if ((tempHyridNotificationModel.locationNotificationModel!.isSharing)) {
      if (tempHyridNotificationModel.locationNotificationModel!.atsignCreator ==
          currentAtSign) {
        // ignore: unawaited_futures
        SendLocationNotification().addMember(SendLocationNotification()
            .locationNotificationModelToLocationDataModel(
                tempHyridNotificationModel.locationNotificationModel!));
      }
    }

    notifyListeners();

    return tempHyridNotificationModel;
  }

  /// Retrieves the value of an AtKey
  Future<dynamic> getAtValue(AtKey key) async {
    try {
      var atvalue =
          await AtClientManager.getInstance().atClient.get(key).catchError(
              // ignore: invalid_return_type_for_catch_error
              (e) => _logger.severe('error in in key_stream_service get $e'));
      // ignore: unnecessary_null_comparison
      if (atvalue != null) {
        return atvalue;
      } else {
        return null;
      }
    } catch (e) {
      _logger.severe('error in key_stream_service getAtValue:$e');
      return null;
    }
  }

  /// Deletes data associated with a LocationNotificationModel
  deleteData(LocationNotificationModel locationNotificationModel) async {
    if (isPastNotification(locationNotificationModel)) {
      notifyListeners();
      return;
    }

    var key = locationNotificationModel.key!;
    var keyKeyword = key.split('-')[0];
    var atkeyMicrosecondId = key.split('-')[1].split('@')[0];
    var response = await AtClientManager.getInstance().atClient.getKeys(
          regex: '$keyKeyword-$atkeyMicrosecondId',
        );
    if (response.isEmpty) {
      return;
    }

    var atkey = getAtKey(response[0]);
    await AtClientManager.getInstance().atClient.delete(atkey);
    removeData(key);
  }

  /// Returns updated list
  void notifyListeners() {
    filterData();

    if (streamAlternative != null) {
      streamAlternative!(allLocationNotifications);
    }

    atNotificationsSink.add(allLocationNotifications);
  }
}
