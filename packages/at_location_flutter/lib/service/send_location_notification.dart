// ignore_for_file: prefer_typing_uninitialized_variables

import 'dart:async';
import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_location_flutter/common_components/custom_toast.dart';
import 'package:at_location_flutter/location_modal/location_data_model.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/service/my_location.dart';
import 'package:at_location_flutter/service/notify_and_put.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';
import 'package:geolocator/geolocator.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

// ignore: implementation_imports
import 'key_stream_service.dart';
import 'package:at_utils/at_logger.dart';

/// [masterSwitchState] will control whether location is sent to any user
///
/// [locationPromptDialog] will be called whenever package is about to send location and [masterSwitchState] is false.
///
/// Make sure that [locationPromptDialog] is a dialog or a function which can ask the user to turn the [masterSwitchState]
/// true if needed.
class SendLocationNotification {
  SendLocationNotification._();

  static final SendLocationNotification _instance =
      SendLocationNotification._();

  factory SendLocationNotification() => _instance;
  Timer? timer;
  final String locationKey = 'location-notify';
  StreamSubscription<Position>? positionStream;
  bool masterSwitchState = true;
  Function? locationPromptDialog;
  Map<String, LocationDataModel> allAtsignsLocationData = {};
  List<String> _atsignsToSendLocationwith = [];
  AtClient? atClient;
  bool isEventInUse = false,
      isLocationDataInitialized = false,
      isEventDataInitialized = false;

  final _logger = AtSignLogger('SendLocationNotification');

  LocationDataModel? getLocationDataModel(String _atsign) =>
      allAtsignsLocationData[_atsign];

  // Enhacement: Write a function to compare new data with saved ones and remove the expired data.

  /// should be called while switching an atsign
  reset() {
    allAtsignsLocationData = {};
    _atsignsToSendLocationwith = [];
    masterSwitchState = true;
    isEventInUse = false;
    isLocationDataInitialized = false;
    isEventDataInitialized = false;
  }

  /// initialises all the variables
  void init(AtClient? newAtClient) {
    if ((timer != null) && (timer!.isActive)) timer!.cancel();
    atClient = newAtClient;
    isEventInUse = AtLocationNotificationListener().isEventInUse;
    if (positionStream != null) positionStream!.cancel();
    findAtSignsToShareLocationWith();
  }

  /// should be called if at_events_flutter package is being used.
  initEventData(List<LocationDataModel> locationDataModel) {
    // _appendLocationDataModelData(locationDataModel);
    compareForMissingInvites(locationDataModel);

    isEventDataInitialized = true;
    if (isLocationDataInitialized) {
      sendLocation();
    }
  }

  /// checks if [_newLocationDataModel] is already present in [allAtsignsLocationData].
  bool ifLocationDataAlreadyExists(LocationDataModel _newLocationDataModel) {
    if (SendLocationNotification()
            .allAtsignsLocationData[_newLocationDataModel.receiver] !=
        null) {
      /// don't add and send again if already present
      var _receiverLocationDataModel = SendLocationNotification()
          .allAtsignsLocationData[_newLocationDataModel.receiver]!;

      if (_newLocationDataModel.locationSharingFor.keys.isEmpty) {
        return false;
      }

      var _id = _newLocationDataModel.locationSharingFor.keys.first;
      if (_receiverLocationDataModel.locationSharingFor[_id] != null) {
        return true;
      }
    }

    return false;
  }

  /// gets all 'location-notify' keys sent from the logged in atsign.
  getAllLocationShareKeys() async {
    var allLocationKeyStrings =
        await AtClientManager.getInstance().atClient.getKeys(
              regex: locationKey,
            );

    await Future.forEach(allLocationKeyStrings, (dynamic key) async {
      if (!'@$key'.contains('cached')) {
        var atKey = getAtKey(key);
        AtValue? _atValue = await KeyStreamService().getAtValue(atKey);
        if ((_atValue != null) && (_atValue.value != null)) {
          try {
            var _locationDataModel =
                LocationDataModel.fromJson(jsonDecode(_atValue.value));
            allAtsignsLocationData[_locationDataModel.receiver] =
                _locationDataModel;
          } catch (e) {
            _logger.severe('Error in getAllLocationData $e');
          }
        }
      }
    });

    checkForExpiredInvites();
  }

  /// checks for expired [LocationDataModel] and removes from [allAtsignsLocationData].
  checkForExpiredInvites() {
    List<String> _idsToDelete = [];
    List<String> _atsignsToDelete = [];

    allAtsignsLocationData.forEach((key, value) {
      allAtsignsLocationData[key]!
          .locationSharingFor
          .forEach((locKey, locValue) {
        if (locValue.to != null && DateTime.now().isAfter(locValue.to!)) {
          _idsToDelete.add(locKey);
        }
      });

      for (var element in _idsToDelete) {
        allAtsignsLocationData[key]!.locationSharingFor.remove(element);
      }

      if (allAtsignsLocationData[key]!.locationSharingFor.isEmpty) {
        _atsignsToDelete.add(key);
      }
    });

    for (var element in _atsignsToDelete) {
      allAtsignsLocationData.remove(element);
    }
  }

  /// looks for newly added [LocationDataModel] and adds to [allAtsignsLocationData].
  compareForMissingInvites(List<LocationDataModel> _newLocationDataModel) {
    for (var _locationDataModel in _newLocationDataModel) {
      if (allAtsignsLocationData[_locationDataModel.receiver] != null) {
        var _receiverLocationDataModel =
            allAtsignsLocationData[_locationDataModel.receiver]!;

        if (_locationDataModel.locationSharingFor.keys.isEmpty) {
          continue;
        }

        var _id = _locationDataModel.locationSharingFor.keys.first;
        if (_receiverLocationDataModel.locationSharingFor[_id] != null) {
          continue;
        } else {
          _receiverLocationDataModel.locationSharingFor = {
            ..._receiverLocationDataModel.locationSharingFor,
            ..._locationDataModel.locationSharingFor
          };

          if (!_atsignsToSendLocationwith
              .contains(_locationDataModel.receiver)) {
            _atsignsToSendLocationwith.add(_locationDataModel.receiver);
          }
        }
      } else {
        allAtsignsLocationData[_locationDataModel.receiver] =
            _locationDataModel;
      }
    }
  }

  /// appends [locationDataModel] to [locationDataModel.receiver].
  _appendLocationDataModelData(List<LocationDataModel> locationDataModel) {
    for (var element in locationDataModel) {
      if (allAtsignsLocationData[element.receiver] != null) {
        allAtsignsLocationData[element.receiver]!.locationSharingFor = {
          ...allAtsignsLocationData[element.receiver]!.locationSharingFor,
          ...element.locationSharingFor
        };
      } else {
        allAtsignsLocationData[element.receiver] = element;
      }
    }
  }

  /// checks for atsigns to share location with.
  void findAtSignsToShareLocationWith() {
    List<LocationDataModel> _newlocationDataModel = [];
    for (var notification in KeyStreamService().allLocationNotifications) {
      LocationDataModel _locationDataModel =
          locationNotificationModelToLocationDataModel(
              notification.locationNotificationModel!);
      _newlocationDataModel.add(_locationDataModel);
    }
    compareForMissingInvites(_newlocationDataModel);

    isLocationDataInitialized = true;
    if ((isEventDataInitialized && isEventInUse) || !isEventInUse) {
      sendLocation();
    }
  }

  void setLocationPrompt(Function _locationPrompt) {
    locationPromptDialog = _locationPrompt;
  }

  /// if state changes then we will send update in next round of location sharing
  void setMasterSwitchState(bool _state) {
    masterSwitchState = _state;
  }

  /// we are assuming that the _newLocationDataModel has a new share id
  /// if it has a same id already in [allAtsignsLocationData[_newLocationDataModel.receiver]]
  /// then we won't add it again
  Future<void> addMember(LocationDataModel _newLocationDataModel) async {
    if (allAtsignsLocationData[_newLocationDataModel.receiver] != null) {
      /// don't add and send again if already present
      var _receiverLocationDataModel =
          allAtsignsLocationData[_newLocationDataModel.receiver]!;

      if (_newLocationDataModel.locationSharingFor.keys.isEmpty) {
        return;
      }

      var _id = _newLocationDataModel.locationSharingFor.keys.first;
      if (_receiverLocationDataModel.locationSharingFor[_id] != null) {
        return;
      }
    }

    // add
    _appendLocationDataModelData([_newLocationDataModel]);

    var locationDataModel = getLocationDataModel(_newLocationDataModel
        .receiver); // get updated (aggregated LocationDataModel)

    if (locationDataModel == null) {
      return;
    }

    var myLocation = await getMyLocation();
    if (myLocation != null) {
      await prepareLocationDataAndSend(
          locationDataModel.receiver, locationDataModel, myLocation);

      if (!masterSwitchState) {
        /// method from main app
        if (locationPromptDialog != null) {
          // _appendLocationDataModelData([locationDataModel]);
          locationPromptDialog!();

          /// return as when main switch is turned on, it will send location to all.
          return;
        }
      }
    } else {
      // ignore: unnecessary_null_comparison
      if (AtLocationNotificationListener().navKey != null) {
        CustomToast().show('Location permission not granted',
            AtLocationNotificationListener().navKey.currentContext!,
            isError: true);
      }
    }
  }

  /// removes a [inviteId] LocationDataModel from [atsignsToRemove] of [allAtsignsLocationData].
  Future<void> removeMember(String inviteId, List<String> atsignsToRemove,
      {bool isSharing = false,
      required bool isExited,
      required bool isAccepted}) async {
    inviteId = trimAtsignsFromKey(inviteId);

    List<String> updatedAtsigns = [], atsignsToDelete = [];
    allAtsignsLocationData.forEach((key, value) {
      for (var atsignToRemove in atsignsToRemove) {
        if ((compareAtSign(key, atsignToRemove)) &&
            (allAtsignsLocationData[key]?.locationSharingFor[inviteId] !=
                null)) {
          allAtsignsLocationData[key]
              ?.locationSharingFor[inviteId]!
              .isAccepted = isAccepted;
          allAtsignsLocationData[key]?.locationSharingFor[inviteId]!.isSharing =
              isSharing;
          allAtsignsLocationData[key]?.locationSharingFor[inviteId]!.isExited =
              isExited;

          updatedAtsigns.add(key);

          // .remove(inviteId);
          // if (allAtsignsLocationData[key]?.locationSharingFor.isEmpty ??
          //     false) {
          //   atsignsToDelete.add(key);
          // } else {
          // so that we dont update and delete the same key
          // updatedAtsigns.add(key);
          // }
        }
      }
    });
    if (updatedAtsigns.isNotEmpty) {
      await sendLocationAfterDataUpdate(updatedAtsigns);
    }

    if (atsignsToDelete.isNotEmpty) {
      await sendNull(atsignsToDelete);
    }
  }

  /// update [allAtsignsLocationData[_newLocationDataModel.receiver]] with new values and sends updated location
  updateExistingLocationDataModel(
      List<LocationDataModel> _newLocationDataModel) async {
    List<String> _atsignsUpdated = [];
    for (var _tempLocationDataModel in _newLocationDataModel) {
      if (ifLocationDataAlreadyExists(_tempLocationDataModel)) {
        allAtsignsLocationData[_tempLocationDataModel.receiver]!
            .locationSharingFor = {
          ...allAtsignsLocationData[_tempLocationDataModel.receiver]!
              .locationSharingFor,
          ..._tempLocationDataModel.locationSharingFor,
        };

        if (!_atsignsUpdated.contains(_tempLocationDataModel.receiver)) {
          _atsignsUpdated.add(_tempLocationDataModel.receiver);
        }
      }
    }

    await SendLocationNotification()
        .sendLocationAfterDataUpdate(_atsignsUpdated);
  }

  /// sends 'location-notify' key with updated [LocationDataModel] to [atsignsUpdated].
  sendLocationAfterDataUpdate(List<String> atsignsUpdated) async {
    var _currentMyLatLng = await getMyLocation();

    await Future.forEach(atsignsUpdated, (String atsign) async {
      if ((allAtsignsLocationData[atsign] != null)) {
        bool isLocSharing = false;

        for (var key
            in allAtsignsLocationData[atsign]!.locationSharingFor.entries) {
          if (allAtsignsLocationData[atsign]!
              .locationSharingFor[key.key]!
              .isSharing) {
            isLocSharing = true;
            break;
          }
        }

        await prepareLocationDataAndSend(
            atsign,
            allAtsignsLocationData[atsign]!,
            (isLocSharing
                ? _currentMyLatLng ?? allAtsignsLocationData[atsign]!.getLatLng
                : null));

        /// send last latLng if _currentMyLatLng is null
      }
    });
  }

  /// sends 'location-notify' to all [allAtsignsLocationData] on every 100 metre location change.
  void sendLocation() async {
    var permission = await Geolocator.checkPermission();

    if (((permission == LocationPermission.always) ||
        (permission == LocationPermission.whileInUse))) {
      positionStream = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(distanceFilter: 100))
          .listen((myLocation) async {
        //// Enhancement: send location only when myLocation has changed
        if (masterSwitchState) {
          for (var field in allAtsignsLocationData.entries) {
            await prepareLocationDataAndSend(field.key, field.value,
                LatLng(myLocation.latitude, myLocation.longitude));
          }
        }
      });
    }
  }

  /// Prepares location data and sends it to the specified receiver
  Future<void> prepareLocationDataAndSend(String receiver,
      LocationDataModel locationData, LatLng? myLocation) async {
    //// don't send anything to logged in atsign
    if (compareAtSign(
        receiver, AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
      return;
    }

    var isSend = false;

    for (var locData in locationData.locationSharingFor.entries) {
      if (locData.value.to == null ||
          DateTime.now().isBefore(locData.value.to!)) {
        isSend = true;
        break;
      }
    }

    //// Enhancement: Send location to only those whose from and to is between DateTime.now()
    // for (var field in locationData.locationSharingFor.entries) {
    //   if ((field.value.from == null) && (field.value.to == null)) {
    //     isSend = true;
    //     break;
    //   }

    //   if (field.value.from != null) {
    //     isSend = true;
    //     if (DateTime.now().isBefore(field.value.from!)) {
    //       isSend = false;
    //     }
    //   }
    // }

    if (isSend) {
      var atKey = newAtKey(
          5000, '$locationKey-${receiver.replaceAll('@', '')}', receiver,
          ttl: null);

      locationData.lat = myLocation?.latitude;
      locationData.long = myLocation?.longitude;

      locationData.lastUpdatedAt = DateTime.now();

      if (!masterSwitchState) {
        locationData.lat = null;
        locationData.long = null;
      }

      //// Enhancement: Uncomment if latLng should be null
      // bool _isSharingLocation = false;
      // locationData.locationSharingFor.forEach((key, value) {
      //   if ((_isSharingLocation) && (value.isSharing)) {
      //     _isSharingLocation = true;
      //   }
      // });

      // if (!_isSharingLocation) {
      //   locationData.lat = null;
      //   locationData.long = null;
      // }

      try {
        var _res = await NotifyAndPut().notifyAndPut(
            atKey, jsonEncode(locationData.toJson()),
            saveDataIfUndelivered: true);

        if (_res) {
          allAtsignsLocationData[receiver] =
              locationData; // update the map if successfully sent
        }
        _logger.finer('send loc data : $_res');
      } catch (e) {
        _logger.severe('error in sending location: $e');
      }
    }
  }

  /// will delete [locationKey] for the atsign and remove from [allAtsignsLocationData]
  Future<bool> sendNull(List<String> atsigns) async {
    var result;

    await Future.forEach(atsigns, (String _atsign) async {
      var atKey =
          newAtKey(-1, '$locationKey-${_atsign.replaceAll('@', '')}', _atsign);
      result = await atClient!.delete(
        atKey,
      );
      if (result) {
        allAtsignsLocationData.remove(_atsign); // remove from map as well
      }
      _logger.finer('result : $result');
    });

    return result;
  }

  /// Deletes all location keys
  void deleteAllLocationKey() async {
    var response = await atClient?.getKeys(
      regex: locationKey,
    );
    await Future.forEach(response ?? [], (dynamic key) async {
      if (!'@$key'.contains('cached')) {
        // the keys i have created
        var atKey = getAtKey(key);
        var result = await atClient!.delete(
          atKey,
        );
        _logger.finer('$key is deleted ? $result');
      }
    });
  }

  /// Creates a new AtKey with the specified parameters
  AtKey newAtKey(int ttr, String key, String sharedWith, {int? ttl}) {
    if (sharedWith[0] != '@') {
      sharedWith = '@$sharedWith';
    }

    String sharedBy = (atClient!.getCurrentAtSign()![0] != '@')
        ? ('@${atClient!.getCurrentAtSign()!}')
        : atClient!.getCurrentAtSign()!;
    var atKey = AtKey()
      ..metadata = Metadata()
      ..metadata.ttr = ttr
      ..metadata.ccd = true
      ..key = key
      ..sharedWith = sharedWith
      ..sharedBy = sharedBy;
    if (ttl != null) atKey.metadata.ttl = ttl;
    return atKey;
  }

  /// converts [LocationNotificationModel] to [LocationDataModel].
  LocationDataModel locationNotificationModelToLocationDataModel(
      LocationNotificationModel locationNotificationModel) {
    return LocationDataModel(
      {
        trimAtsignsFromKey(locationNotificationModel.key!): LocationSharingFor(
            locationNotificationModel.from,
            locationNotificationModel.to,
            LocationSharingType.P2P,
            locationNotificationModel.isAccepted,
            locationNotificationModel.isExited,
            locationNotificationModel.isSharing)
      },
      null,
      null,
      DateTime.now(),
      locationNotificationModel.atsignCreator!,
      locationNotificationModel.receiver!,
    );
  }
}
