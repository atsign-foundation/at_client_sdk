// ignore_for_file: prefer_const_constructors, invalid_use_of_visible_for_testing_member, avoid_function_literals_in_foreach_calls

import 'dart:async';
// import 'package:at_chat_flutter/at_chat_flutter.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_events_flutter/common_components/floating_icon.dart';
import 'package:at_events_flutter/models/event_key_location_model.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/services/at_event_notification_listener.dart';
import 'package:at_location_flutter/at_location_flutter.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'events_collapsed_content.dart';

class EventsMapScreenData {
  EventsMapScreenData._();
  static final EventsMapScreenData _instance = EventsMapScreenData._();
  factory EventsMapScreenData() => _instance;

  ValueNotifier<EventNotificationModel?>? eventNotifier;
  // late List<HybridModel> markers;
  late List<String?> exitedAtSigns;
  int count = 0;

  /// moves to the event screen with the given EventNotificationModel
  void moveToEventScreen(EventNotificationModel _eventNotificationModel) async {
    // markers = [];
    exitedAtSigns = [];
    _initChat(_eventNotificationModel);
    _calculateExitedAtsigns(_eventNotificationModel);
    eventNotifier = ValueNotifier(_eventNotificationModel);
    // markers.add(addVenueMarker(_eventNotificationModel));

    // ignore: unawaited_futures
    Navigator.push(
      AtEventNotificationListener().navKey!.currentContext!,
      MaterialPageRoute(
        builder: (context) => _EventsMapScreen(),
      ),
    );

    // markers =
    // var _hybridModelList =
    //     await _calculateHybridModelList(_eventNotificationModel);
    // _hybridModelList.forEach((element) {
    //   markers.add(element);
    // });
    // ignore: invalid_use_of_protected_member
    eventNotifier!.notifyListeners();
  }

  /// calculates the AtSigns of members who have exited the event in the given EventNotificationModel
  void _calculateExitedAtsigns(EventNotificationModel _event) {
    _event.group!.members!.forEach((element) {
      if ((element.tags!['isExited']) && (!element.tags!['isAccepted'])) {
        exitedAtSigns.add(element.atSign);
      }
    });
  }

  /// updates event data from a list of EventKeyLocationModel objects
  // ignore: prefer_final_fields
  List<List<EventKeyLocationModel>> _listOfLists = [];
  bool _updating = false;
  void updateEventdataFromList(List<EventKeyLocationModel> _list) async {
    _listOfLists.add(_list);
    if (!_updating) {
      _startUpdating();
    }
  }

  /// starts the updating process for event data
  void _startUpdating() async {
    _updating = true;
    for (var i = 0; i < _listOfLists.length; i++) {
      var _obj = _listOfLists.removeAt(0);
      await _updateEventdataFromList(_obj);
    }
    _updating = false;
  }

  /// updates event data from a list of EventKeyLocationModel objects
  Future<void> _updateEventdataFromList(
      List<EventKeyLocationModel> _list) async {
    count++;
    if (eventNotifier != null) {
      for (var i = 0; i < _list.length; i++) {
        if (_list[i].eventNotificationModel!.key == eventNotifier!.value!.key) {
          exitedAtSigns = [];
          _calculateExitedAtsigns(_list[i].eventNotificationModel!);

          // markers = [];

          // markers.add(addVenueMarker(_list[i].eventNotificationModel!));

          // var _hybridModelList =
          //     await _calculateHybridModelList(_list[i].eventNotificationModel!);
          // _hybridModelList.forEach((element) {
          //   markers.add(element);
          // });

          eventNotifier!.value = _list[i].eventNotificationModel;
          // ignore: invalid_use_of_protected_member
          eventNotifier!.notifyListeners();

          count--;
          break;
        }
      }
    }
  }

  /// adds a venue marker to the event
  HybridModel addVenueMarker(EventNotificationModel _event) {
    var _eventHybridModel = HybridModel(
        displayName: _event.venue!.label,
        latLng: LatLng(_event.venue!.latitude!, _event.venue!.longitude!),
        eta: '?',
        image: null);
    _eventHybridModel.marker = buildMarker(_eventHybridModel);
    return _eventHybridModel;
  }

  /// initializes the chat for the event
  // ignore: always_declare_return_types
  _initChat(EventNotificationModel _event) async {
    await _getAtSignAndInitializeChat();
    _setAtsignToChatWith(_event);
  }

  /// retrieves the current AtSign and initializes the chat
  // ignore: always_declare_return_types
  _getAtSignAndInitializeChat() async {}

  /// sets the AtSign to chat with for the event
  // ignore: always_declare_return_types
  _setAtsignToChatWith(EventNotificationModel _event) {
    var groupMembers = <String>[];
    groupMembers.add(_event.atsignCreator!);
    _event.group?.members?.forEach((member) {
      groupMembers.add(member.atSign!);
    });
    groupMembers.remove(AtEventNotificationListener().currentAtSign);
    var atkeyMicrosecondId = _event.key!.split('createevent-')[1].split('@')[0];
    if ((AtEventNotificationListener()
                .atClientManager
                .atClient
                .getPreferences() !=
            null) &&
        (AtEventNotificationListener()
                .atClientManager
                .atClient
                .getPreferences()!
                .namespace !=
            null)) {
      atkeyMicrosecondId = atkeyMicrosecondId.replaceAll(
          '.${AtEventNotificationListener().atClientManager.atClient.getPreferences()!.namespace!}',
          '');
    }
    // setChatWithAtSign('',
    //     isGroup: true, groupId: atkeyMicrosecondId, groupMembers: groupMembers);
  }

  void dispose() {
    eventNotifier = null;
    // markers = [];
    exitedAtSigns = [];
  }
}

class _EventsMapScreen extends StatefulWidget {
  const _EventsMapScreen({Key? key}) : super(key: key);

  @override
  _EventsMapScreenState createState() => _EventsMapScreenState();
}

class _EventsMapScreenState extends State<_EventsMapScreen> {
  final PanelController pc = PanelController();
  bool snackbarShownOnce = false;
  GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    EventsMapScreenData().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      body: SafeArea(
        child: Container(
          alignment: Alignment.center,
          child: ValueListenableBuilder(
            valueListenable: EventsMapScreenData().eventNotifier!,
            builder: (BuildContext context, EventNotificationModel? _event,
                Widget? child) {
              List<String?> atsignsToTrack = [];

              if (_event!.atsignCreator !=
                  AtClientManager.getInstance().atClient.getCurrentAtSign()!) {
                atsignsToTrack.add(_event.atsignCreator);
              }

              for (var member in _event.group!.members!) {
                if ((member.atSign!) !=
                    AtClientManager.getInstance()
                        .atClient
                        .getCurrentAtSign()!) {
                  atsignsToTrack.add(member.atSign!);
                }
              }

              return Stack(
                children: [
                  AtLocationFlutterPlugin(
                    atsignsToTrack,
                    addCurrentUserMarker: true,
                    calculateETA: true,
                    etaFrom: LatLng(
                        _event.venue!.latitude!, _event.venue!.longitude!),
                    textForCenter: _event.venue!.label,
                    notificationID: _event.key,
                    refreshAt: _event.event!.startTime,
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: FloatingIcon(
                      icon: Icons.arrow_back,
                      isTopLeft: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  SlidingUpPanel(
                    controller: pc,
                    minHeight: 205.toHeight,
                    maxHeight: 431.toHeight,
                    panel: EventsCollapsedContent(
                      _event,
                      key: UniqueKey(),
                    ),
                  )
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
