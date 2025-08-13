// ignore_for_file: prefer_typing_uninitialized_variables, unnecessary_null_comparison

import 'dart:async';
import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_location_flutter/common_components/custom_toast.dart';
import 'package:at_location_flutter/location_modal/key_location_model.dart';
import 'package:at_location_flutter/location_modal/location_data_model.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/screens/notification_dialog/notification_dialog.dart';
import 'package:at_location_flutter/service/key_stream_service.dart';
import 'package:at_location_flutter/service/master_location_service.dart';
import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:at_location_flutter/utils/constants/constants.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';

import 'request_location_service.dart';
import 'sharing_location_service.dart';

/// Starts monitor and listens for notifications related to this package.
class AtLocationNotificationListener {
  AtLocationNotificationListener._();

  static final _instance = AtLocationNotificationListener._();

  factory AtLocationNotificationListener() => _instance;
  final String locationKey = 'location-notify';
  AtClient? atClientInstance;
  String? currentAtSign;
  late bool showDialogBox;
  late GlobalKey<NavigatorState> navKey;
  bool isEventInUse = false, monitorStarted = false;
  final _logger = AtSignLogger('AtLocationNotificationListener');

  /// called when switching atsign
  resetMonitor() {
    monitorStarted = false;
  }

  // ignore: non_constant_identifier_names
  String? ROOT_DOMAIN;

  void init(GlobalKey<NavigatorState> navKeyFromMainApp, String rootDomain,
      bool showDialogBox,
      {Function? newGetAtValueFromMainApp, bool isEventInUse = false}) {
    this.isEventInUse = isEventInUse;
    atClientInstance = AtClientManager.getInstance().atClient;
    currentAtSign = AtClientManager.getInstance().atClient.getCurrentAtSign();
    navKey = navKeyFromMainApp;
    this.showDialogBox = showDialogBox;
    ROOT_DOMAIN = rootDomain;

    startMonitor();
  }

  /// starts monitor to receive incoming notifications.
  Future<void> startMonitor() async {
    if (!monitorStarted) {
      AtClientManager.getInstance()
          .atClient
          .notificationService
          .subscribe(shouldDecrypt: true)
          .listen((monitorNotification) {
        _notificationCallback(monitorNotification);
      });
      monitorStarted = true;
    }
  }

  ///Fetches privatekey for [atsign] from device keychain.
  Future<String?> getPrivateKey(String atsign) async {
    return await KeyChainManager.getInstance().getPkamPrivateKey(atsign);
  }

  /// filters out the received notification.
  void _notificationCallback(AtNotification notification) async {
    if ((notification.id == '-1') ||
        compareAtSign(notification.from,
            AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
      return;
    }

    var value = notification.value;
    var notificationKey = notification.key;
    _logger.finer(
        '_notificationCallback notification received in location package ===========> :$notification , notification key: $notificationKey');
    var fromAtSign = notification.from;
    var atKey;
    if (notificationKey.toString().contains(':')) {
      atKey = notificationKey.split(':')[1];
    } else {
      atKey = notificationKey;
    }

    if ((!notificationKey.contains(locationKey)) &&
        (!notificationKey
            .contains(MixedConstants.DELETE_REQUEST_LOCATION_ACK)) &&
        (!notificationKey.contains(MixedConstants.SHARE_LOCATION_ACK)) &&
        (!notificationKey.contains(MixedConstants.SHARE_LOCATION)) &&
        (!notificationKey.contains(MixedConstants.REQUEST_LOCATION_ACK)) &&
        (!notificationKey.contains(MixedConstants.REQUEST_LOCATION))) {
      _logger.finer(
          'returned from _notificationCallback in location package ===========>');
      return;
    }

    var operation = notification.operation;

    if (operation == 'delete') {
      if (atKey.toString().toLowerCase().contains(locationKey)) {
        _logger.finer('$notificationKey deleted');
        MasterLocationService().deleteReceivedData(fromAtSign);
        return;
      }

      if (atKey
          .toString()
          .toLowerCase()
          .contains(MixedConstants.SHARE_LOCATION)) {
        _logger.finer('$notificationKey containing sharelocation deleted');
        KeyStreamService().removeData(atKey.toString());
        return;
      }

      if (atKey
          .toString()
          .toLowerCase()
          .contains(MixedConstants.REQUEST_LOCATION)) {
        _logger.finer('$notificationKey containing requestlocation deleted');
        KeyStreamService().removeData(atKey.toString());
        return;
      }
    }

    var decryptedMessage = value;

    if (decryptedMessage == null || decryptedMessage == '') {
      return;
    }

    if (atKey
        .toString()
        .toLowerCase()
        .contains(MixedConstants.DELETE_REQUEST_LOCATION_ACK)) {
      var msg =
          LocationNotificationModel.fromJson(jsonDecode(decryptedMessage));
      // ignore: unawaited_futures
      RequestLocationService().deleteKey(msg);
      return;
    }

    if (atKey.toString().toLowerCase().contains(locationKey)) {
      var msg = LocationDataModel.fromJson(jsonDecode(decryptedMessage));
      MasterLocationService().updateHybridList(msg);
      return;
    }

    if (atKey
        .toString()
        .toLowerCase()
        .contains(MixedConstants.SHARE_LOCATION_ACK)) {
      var locationData =
          LocationNotificationModel.fromJson(jsonDecode(decryptedMessage));
      // ignore: unawaited_futures
      SharingLocationService().updateWithShareLocationAcknowledge(locationData);
      return;
    }

    if (atKey
        .toString()
        .toLowerCase()
        .contains(MixedConstants.SHARE_LOCATION)) {
      var locationData =
          LocationNotificationModel.fromJson(jsonDecode(decryptedMessage));
      if (locationData.isAcknowledgment == true) {
        KeyStreamService().mapUpdatedLocationDataToWidget(locationData);
        // if (locationData.rePrompt) {
        //   await showMyDialog(fromAtSign, locationData);
        // }
      } else {
        var _result = await KeyStreamService()
            .addDataToList(locationData, receivedkey: notificationKey);
        if (_result is KeyLocationModel) {
          showToast('$fromAtSign did a share location', navKey.currentContext!);
        }
      }
      return;
    }

    if (atKey
        .toString()
        .toLowerCase()
        .contains(MixedConstants.REQUEST_LOCATION_ACK)) {
      var locationData =
          LocationNotificationModel.fromJson(jsonDecode(decryptedMessage));
      // ignore: unawaited_futures
      RequestLocationService()
          .updateWithRequestLocationAcknowledge(locationData);
      return;
    }

    if (atKey
        .toString()
        .toLowerCase()
        .contains(MixedConstants.REQUEST_LOCATION)) {
      var locationData =
          LocationNotificationModel.fromJson(jsonDecode(decryptedMessage));
      if (locationData.isAcknowledgment == true) {
        if (!(KeyStreamService().isPastNotification(locationData))) {
          KeyStreamService().mapUpdatedLocationDataToWidget(locationData);
          if (locationData.rePrompt) {
            await showMyDialog(fromAtSign, locationData);
          }
        }
      } else {
        /// if this fails, then all subsequent calls for this locationData will fail
        var _result = await KeyStreamService()
            .addDataToList(locationData, receivedkey: notificationKey);
        if (_result is KeyLocationModel) {
          await showMyDialog(fromAtSign, locationData);
        }
      }
      return;
    }
  }

  /// Shows a custom notification dialog
  Future<void> showMyDialog(
      String? fromAtSign, LocationNotificationModel locationData) async {
    if (showDialogBox) {
      return showDialog<void>(
        context: navKey.currentContext!,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return NotificationDialog(
            userName: fromAtSign,
            locationData: locationData,
            key: UniqueKey(),
          );
        },
      );
    }
  }

  /// Shows a toast message
  showToast(String msg, BuildContext _context,
      {bool isError = false, bool isSuccess = true}) {
    try {
      ScaffoldMessenger.of(_context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AllColors().RED : AllColors().GREEN,
        dismissDirection: DismissDirection.horizontal,
      ));
    } catch (e) {
      CustomToast().show(msg, navKey.currentContext!,
          isError: isError, isSuccess: isSuccess);
    }
  }

  /// Returns the key type based on a given key regex
  String getKeyType(String keyRegex) {
    if (keyRegex.contains(MixedConstants.SHARE_LOCATION)) {
      return 'Share location';
    }

    if (keyRegex.contains(MixedConstants.REQUEST_LOCATION_ACK)) {
      return 'Request location acknowledgment';
    }

    if (keyRegex.contains(MixedConstants.REQUEST_LOCATION)) {
      return 'Request location';
    }

    return '';
  }
}
