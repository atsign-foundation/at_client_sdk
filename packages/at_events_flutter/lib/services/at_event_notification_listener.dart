// ignore_for_file: unnecessary_null_comparison, unused_local_variable

import 'dart:async';
import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_contacts_flutter/utils/init_contacts_service.dart';
import 'package:at_events_flutter/models/event_key_location_model.dart';
import 'package:at_events_flutter/models/event_member_location.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/screens/notification_dialog/event_notification_dialog.dart';
import 'package:at_events_flutter/services/event_key_stream_service.dart';
import 'package:at_events_flutter/utils/constants.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';
import 'package:flutter/material.dart';
import 'package:at_utils/at_logger.dart';

/// Starts monitor and listens for notifications related to this package.
class AtEventNotificationListener {
  AtEventNotificationListener._();
  static final _instance = AtEventNotificationListener._();
  factory AtEventNotificationListener() => _instance;
  late AtClientManager atClientManager;
  bool monitorStarted = false;
  String? currentAtSign;
  GlobalKey<NavigatorState>? navKey;
  // ignore: non_constant_identifier_names
  String? ROOT_DOMAIN;

  final _logger = AtSignLogger('AtEventNotificationListener');

  /// called when switching atsign
  resetMonitor() {
    monitorStarted = false;
  }

  /// initializes initial values and configurations for the package
  void init(GlobalKey<NavigatorState> navKeyFromMainApp, String rootDomain,
      {Function? newGetAtValueFromMainApp}) {
    atClientManager = AtClientManager.getInstance();
    currentAtSign = AtClientManager.getInstance().atClient.getCurrentAtSign();

    initializeContactsService(rootDomain: rootDomain);

    navKey = navKeyFromMainApp;
    ROOT_DOMAIN = rootDomain;
    startMonitor();
  }

  /// starts monitor to receive incoming notifications.
  Future<bool> startMonitor() async {
    if (!monitorStarted) {
      AtClientManager.getInstance()
          .atClient
          .notificationService
          .subscribe(shouldDecrypt: true)
          .listen((notification) {
        _notificationCallback(notification);
      });
      monitorStarted = true;
    }

    return true;
  }

  /// filters out the received notification.
  void _notificationCallback(AtNotification notification) async {
    if ((notification.id == '-1') ||
        compareAtSign(notification.from,
            AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
      return;
    }

    _logger.finer(
        'notification received in events package ===========> $notification');
    var value = notification.value;
    var notificationKey = notification.key;
    var fromAtSign = notification.from;

    if ((!notificationKey.contains('createevent')) &&
        (!notificationKey.contains('eventacknowledged')) &&
        (!notificationKey.contains(MixedConstants.EVENT_MEMBER_LOCATION_KEY))) {
      _logger.finer(
          'returned from _notificationCallback in events package ===========>');
      return;
    }

    var operation = notification.operation;
    if ((operation == 'delete') &&
        notificationKey.toString().toLowerCase().contains('createevent')) {
      // EventService().removeDeletedEventFromList(notificationKey);
      return;
    }

    var decryptedMessage = value;

    _logger.finer('decrypted message:$decryptedMessage');

    if (decryptedMessage == null || decryptedMessage == '') {
      return;
    }

    if (notificationKey.toString().contains('createevent')) {
      var eventData =
          EventNotificationModel.fromJson(jsonDecode(decryptedMessage));
      if ((eventData.isUpdate != null && eventData.isUpdate == false) ||
          !EventKeyStreamService().isEventSharedWithMe(eventData)) {
        // new event received
        // show dialog
        // add in event list
        var _result = await EventKeyStreamService()
            .addDataToList(eventData, receivedkey: notificationKey);
        if (_result is EventKeyLocationModel) {
          await showMyDialog(eventNotificationModel: eventData);
        }
      } else if (eventData.isUpdate!) {
        // event updated received
        // update event list
        EventKeyStreamService().mapUpdatedEventDataToWidget(eventData);
      }

      return;
    }

    if (notificationKey.toString().contains('eventacknowledged')) {
      var msg = EventNotificationModel.fromJson(jsonDecode(decryptedMessage));

      // EventKeyStreamService().createEventAcknowledge(msg, fromAtSign);
      return;
    }

    if (notificationKey
        .toString()
        .contains(MixedConstants.EVENT_MEMBER_LOCATION_KEY)) {
      var msg = EventMemberLocation.fromJson(jsonDecode(decryptedMessage));

      // EventKeyStreamService().updateLocationData(msg, fromAtSign);
      return;
    }
  }

  /// shows a dialog with event notification details
  Future<void> showMyDialog(
      {EventNotificationModel? eventNotificationModel}) async {
    return showDialog<void>(
      context: navKey!.currentContext!,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return EventNotificationDialog(
          eventData: eventNotificationModel,
          key: UniqueKey(),
        );
      },
    );
  }
}
