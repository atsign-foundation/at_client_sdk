// ignore_for_file: unused_local_variable, avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_events_flutter/at_events_flutter.dart';
import 'package:at_events_flutter/models/enums_model.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/services/at_event_notification_listener.dart';
import 'package:at_events_flutter/services/venues_services.dart';
import 'package:at_events_flutter/utils/constants.dart';
import 'package:at_location_flutter/location_modal/location_data_model.dart';
import 'package:at_location_flutter/service/send_location_notification.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';

import 'contact_service.dart';
import 'package:at_utils/at_logger.dart';

class EventKeyStreamService {
  EventKeyStreamService._();
  static final EventKeyStreamService _instance = EventKeyStreamService._();
  factory EventKeyStreamService() => _instance;

  final _logger = AtSignLogger('EventKeyStreamService');

  late AtClientManager atClientManager;
  AtContactsImpl? atContactImpl;
  AtContact? loggedInUserDetails;
  List<EventKeyLocationModel> allEventNotifications = [],
      allPastEventNotifications = [];
  String? currentAtSign;
  List<AtContact> contactList = [];

  /// streamController for AT notifications
  // ignore: close_sinks
  StreamController atNotificationsController =
      StreamController<List<EventKeyLocationModel>>.broadcast();
  Stream<List<EventKeyLocationModel>> get atNotificationsStream =>
      atNotificationsController.stream as Stream<List<EventKeyLocationModel>>;
  StreamSink<List<EventKeyLocationModel>> get atNotificationsSink =>
      atNotificationsController.sink as StreamSink<List<EventKeyLocationModel>>;

  Function(List<EventKeyLocationModel>)? streamAlternative;

  /// initializes with necessary values and configurations
  void init({Function(List<EventKeyLocationModel>)? streamAlternative}) async {
    loggedInUserDetails = null;
    atClientManager = AtClientManager.getInstance();
    currentAtSign = atClientManager.atClient.getCurrentAtSign();
    allEventNotifications = [];
    allPastEventNotifications = [];
    this.streamAlternative = streamAlternative;

    await VenuesServices().getVenues();

    atNotificationsController =
        StreamController<List<EventKeyLocationModel>>.broadcast();
    getAllEventNotifications();

    loggedInUserDetails = await getAtSignDetails(currentAtSign);
    getAllContactDetails(currentAtSign!);
  }

  /// retrieves all contact details for the given [currentAtSign]
  void getAllContactDetails(String currentAtSign) async {
    atContactImpl = await AtContactsImpl.getInstance(currentAtSign);
    contactList = await atContactImpl!.listContacts();
  }

  /// adds all 'createevent' notifications to [atNotificationsSink]
  void getAllEventNotifications() async {
    AtClientManager.getInstance().atClient.syncService.sync();

    var response = await atClientManager.atClient.getKeys(
      regex: 'createevent-',
    );

    if (response.isEmpty) {
      SendLocationNotification().initEventData([]);
      notifyListeners();
      return;
    }

    await Future.forEach(response, (String key) async {
      var _atKey = getAtKey(key);
      AtValue? value = await getAtValue(_atKey);
      if (value != null) {
        try {
          if ((value.value != null) && (value.value != 'null')) {
            var eventNotificationModel =
                EventNotificationModel.fromJson(jsonDecode(value.value));

            // ignore: todo
            ///// TODO: Uncomment if any issues with keys
            // eventNotificationModel.key = key;

            allEventNotifications.insert(
                0,
                EventKeyLocationModel(
                    eventNotificationModel:
                        eventNotificationModel)); // last item to come in would be at the top of the list
          }
        } catch (e) {
          _logger.severe('convertJsonToLocationModel error :$e');
        }
      }
    });

    filterPastEventsFromList();
    await checkForPendingEvents();
    notifyListeners();
    calculateLocationSharingAllEvents(initLocationSharing: true);
  }

  /// Removes past notifications and notification where data is null.
  void filterPastEventsFromList() {
    for (var i = 0; i < allEventNotifications.length; i++) {
      if (allEventNotifications[i]
              .eventNotificationModel!
              .event!
              .endTime!
              .difference(DateTime.now())
              .inMinutes <
          0) allPastEventNotifications.add(allEventNotifications[i]);
    }

    allEventNotifications
        .removeWhere((element) => allPastEventNotifications.contains(element));
  }

  /// Updates any received notification with [haveResponded] true, if already responded.
  Future<void> checkForPendingEvents() async {
    // ignore: avoid_function_literals_in_foreach_calls
    allEventNotifications.forEach((notification) async {
      notification.eventNotificationModel!.group!.members!
          // ignore: avoid_function_literals_in_foreach_calls
          .forEach((member) async {
        if ((member.atSign == currentAtSign) &&
            (member.tags!['isAccepted'] == false) &&
            (member.tags!['isExited'] == false)) {
          var atkeyMicrosecondId = notification.eventNotificationModel!.key!
              .split('createevent-')[1]
              .split('@')[0];
          var acknowledgedKeyId = 'eventacknowledged-$atkeyMicrosecondId';
          var allRegexResponses =
              await atClientManager.atClient.getKeys(regex: acknowledgedKeyId);
          // ignore: unnecessary_null_comparison
          if ((allRegexResponses != null) && (allRegexResponses.isNotEmpty)) {
            notification.haveResponded = true;
          }
        }
      });
    });
  }

  /// returns [true] if [eventNotificationModel] is a past event
  isPastNotification(EventNotificationModel eventNotificationModel) {
    if (eventNotificationModel.event!.endTime!.isBefore(DateTime.now())) {
      return true;
    }

    return false;
  }

  /// Adds new [EventKeyLocationModel] data for new received notification
  Future<dynamic> addDataToList(EventNotificationModel eventNotificationModel,
      {String? receivedkey}) async {
    /// so, that we don't add any expired event
    if (isPastNotification(eventNotificationModel)) {
      return;
    }

    /// with rSDK we can get previous notification, this will restrict us to add one notification twice
    for (var _eventNotification in allEventNotifications) {
      if (_eventNotification.eventNotificationModel != null &&
          _eventNotification.eventNotificationModel!.key ==
              eventNotificationModel.key) {
        return;
      }
    }

    var tempEventKeyLocationModel = EventKeyLocationModel();
    tempEventKeyLocationModel.eventNotificationModel = eventNotificationModel;
    allEventNotifications.insert(0,
        tempEventKeyLocationModel); // last item to come in would be at the top of the list

    notifyListeners();

    /// Add in SendLocation map only if I am creator,
    /// for members, will be added on first action on the event
    if (compareAtSign(eventNotificationModel.atsignCreator!, currentAtSign!)) {
      await checkLocationSharingForEventData(
          tempEventKeyLocationModel.eventNotificationModel!);
    }

    return tempEventKeyLocationModel;
  }

  /// Updates any [EventKeyLocationModel] data for updated data
  Future<void> mapUpdatedEventDataToWidget(EventNotificationModel eventData,
      {Map<dynamic, dynamic>? tags,
      String? tagOfAtsign,
      bool updateLatLng = false,
      bool updateOnlyCreator = false}) async {
    String neweventDataKeyId;
    neweventDataKeyId = eventData.key!
        .split('${MixedConstants.CREATE_EVENT}-')[1]
        .split('@')[0];

    for (var i = 0; i < allEventNotifications.length; i++) {
      if (allEventNotifications[i]
          .eventNotificationModel!
          .key!
          .contains(neweventDataKeyId)) {
        /// if we want to update everything
        // allEventNotifications[i].eventNotificationModel = eventData;

        /// For events send tags of group members if we have and update only them
        if (updateOnlyCreator) {
          /// So that creator doesnt update group details
          eventData.group =
              allEventNotifications[i].eventNotificationModel!.group;
        }

        if ((tags != null) && (tagOfAtsign != null)) {
          allEventNotifications[i]
              .eventNotificationModel!
              .group!
              .members!
              .where((element) => element.atSign == tagOfAtsign)
              .forEach((element) {
            if (updateLatLng) {
              element.tags!['lat'] = tags['lat'];
              element.tags!['long'] = tags['long'];
            } else {
              element.tags = tags;
            }
          });
        } else {
          allEventNotifications[i].eventNotificationModel = eventData;
        }

        allEventNotifications[i].eventNotificationModel!.key =
            allEventNotifications[i].eventNotificationModel!.key;

        notifyListeners();

        await updateLocationDataForExistingEvent(eventData);

        break;
      }
    }
  }

  /// updates [eventData] in [SendLocationNotification().allAtsignsLocationData]
  updateLocationDataForExistingEvent(EventNotificationModel eventData) async {
    var _allAtsigns = getAtsignsFromEvent(eventData);
    List<String> _atsignsToSend = [];

    for (var _atsign in _allAtsigns) {
      if (SendLocationNotification().allAtsignsLocationData[_atsign] != null) {
        var _locationSharingForMap =
            SendLocationNotification().allAtsignsLocationData[_atsign];
        var _fromAndTo = getFromAndToForEvent(eventData);

        var _locFor = _locationSharingForMap!
            .locationSharingFor[trimAtsignsFromKey(eventData.key!)];

        if (_locFor != null) {
          if (_locFor.from != _fromAndTo['from']) {
            SendLocationNotification()
                .allAtsignsLocationData[_atsign]!
                .locationSharingFor[trimAtsignsFromKey(eventData.key!)]!
                .from = _fromAndTo['from'];

            if (!_atsignsToSend.contains(_atsign)) {
              _atsignsToSend.add(_atsign);
            }
          }
          if (_locFor.to != _fromAndTo['to']) {
            SendLocationNotification()
                .allAtsignsLocationData[_atsign]!
                .locationSharingFor[trimAtsignsFromKey(eventData.key!)]!
                .to = _fromAndTo['to'];

            if (!_atsignsToSend.contains(_atsign)) {
              _atsignsToSend.add(_atsign);
            }
          }

          continue;
        }
      }

      /// add if doesn not exist
      var _newLocationDataModel =
          eventNotificationToLocationDataModel(eventData, [_atsign])[0];

      /// if exists, then get booleans from some already existing data
      for (var _existingAtsign in _allAtsigns) {
        if ((SendLocationNotification()
                    .allAtsignsLocationData[_existingAtsign] !=
                null) &&
            (SendLocationNotification()
                    .allAtsignsLocationData[_existingAtsign]!
                    .locationSharingFor[trimAtsignsFromKey(eventData.key!)] !=
                null)) {
          var _locFor = SendLocationNotification()
              .allAtsignsLocationData[_existingAtsign]!
              .locationSharingFor[trimAtsignsFromKey(eventData.key!)];

          _newLocationDataModel
              .locationSharingFor[trimAtsignsFromKey(eventData.key!)]!
              .isAccepted = _locFor!.isAccepted;
          _newLocationDataModel
              .locationSharingFor[trimAtsignsFromKey(eventData.key!)]!
              .isExited = _locFor.isExited;
          _newLocationDataModel
              .locationSharingFor[trimAtsignsFromKey(eventData.key!)]!
              .isSharing = _locFor.isSharing;

          break;
        }
      }

      /// add/append accordingly
      if (SendLocationNotification().allAtsignsLocationData[_atsign] != null) {
        /// if atsigns exists append locationSharingFor
        SendLocationNotification()
            .allAtsignsLocationData[_atsign]!
            .locationSharingFor = {
          ...SendLocationNotification()
              .allAtsignsLocationData[_atsign]!
              .locationSharingFor,
          ..._newLocationDataModel.locationSharingFor,
        };
      } else {
        SendLocationNotification().allAtsignsLocationData[_atsign] =
            _newLocationDataModel;
      }

      if (!_atsignsToSend.contains(_atsign)) {
        _atsignsToSend.add(_atsign);
      }
    }
    await SendLocationNotification()
        .sendLocationAfterDataUpdate(_atsignsToSend);
  }

  /// if [eventData] is already present in [allEventNotifications].
  bool isEventSharedWithMe(EventNotificationModel eventData) {
    for (var i = 0; i < allEventNotifications.length; i++) {
      if (allEventNotifications[i]
          .eventNotificationModel!
          .key!
          .contains(eventData.key!)) {
        return true;
      }
    }
    return false;
  }

  /// Checks current status of [currentAtSign] in an event and updates [SendLocationNotification] location sending list.
  Future<void> checkLocationSharingForEventData(
      EventNotificationModel eventNotificationModel) async {
    if ((eventNotificationModel.atsignCreator == currentAtSign)) {
      if (eventNotificationModel.isSharing!) {
        // ignore: unawaited_futures
        await calculateLocationSharingForSingleEvent(eventNotificationModel);
      } else {
        List<String> atsignsToremove = [];
        for (var member in eventNotificationModel.group!.members!) {
          atsignsToremove.add(member.atSign!);
        }
        SendLocationNotification().removeMember(
            eventNotificationModel.key!, atsignsToremove,
            isAccepted: !eventNotificationModel.isCancelled!,
            isExited: eventNotificationModel.isCancelled!);
      }
    } else {
      await calculateLocationSharingForSingleEvent(eventNotificationModel);
    }
  }

  /// Processes any kind of update in an event and notifies creator/members
  Future<bool> actionOnEvent(
      EventNotificationModel event, ATKEY_TYPE_ENUM keyType,
      {required bool isAccepted,
      required bool isSharing,
      required bool isExited,
      bool? isCancelled}) async {
    var eventData = EventNotificationModel.fromJson(jsonDecode(
        EventNotificationModel.convertEventNotificationToJson(event)));

    try {
      if (isCancelled == true) {
        await updateEventMemberInfo(eventData,
            isAccepted: false, isExited: true, isSharing: false);
      } else {
        await updateEventMemberInfo(eventData,
            isAccepted: isAccepted, isExited: isExited, isSharing: isSharing);
      }

      notifyListeners();

      return true;
    } catch (e) {
      _logger.severe('error in updating event $e');
      return false;
    }
  }

  /// return all atsigns in an event except the logged in user.
  List<String> getAtsignsFromEvent(EventNotificationModel _event) {
    List<String> _allAtsignsInEvent = [];

    if (!compareAtSign(_event.atsignCreator!,
        AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
      _allAtsignsInEvent.add(_event.atsignCreator!);
    }

    if (_event.group!.members!.isNotEmpty) {
      Set<AtContact>? groupMembers = _event.group!.members!;

      // ignore: avoid_function_literals_in_foreach_calls
      groupMembers.forEach((member) {
        if (!compareAtSign(member.atSign!,
            AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
          _allAtsignsInEvent.add(member.atSign!);
        }
      });
    }

    return _allAtsignsInEvent;
  }

  /// updates [SendLocationNotification().allAtsignsLocationData] for the [_event].
  updateEventMemberInfo(EventNotificationModel _event,
      {required bool isAccepted,
      required bool isSharing,
      required bool isExited}) async {
    String _id = trimAtsignsFromKey(_event.key!);

    List<String> _allAtsignsInEvent = getAtsignsFromEvent(_event);

    for (var _atsign in _allAtsignsInEvent) {
      if (SendLocationNotification().allAtsignsLocationData[_atsign] != null) {
        if (SendLocationNotification()
                .allAtsignsLocationData[_atsign]!
                .locationSharingFor[_id] !=
            null) {
          SendLocationNotification()
              .allAtsignsLocationData[_atsign]!
              .locationSharingFor[_id]!
              .isAccepted = isAccepted;

          SendLocationNotification()
              .allAtsignsLocationData[_atsign]!
              .locationSharingFor[_id]!
              .isSharing = isSharing;

          SendLocationNotification()
              .allAtsignsLocationData[_atsign]!
              .locationSharingFor[_id]!
              .isExited = isExited;
        } else {
          var _fromAndTo = getFromAndToForEvent(_event);
          SendLocationNotification()
                  .allAtsignsLocationData[_atsign]!
                  .locationSharingFor[_id] =
              LocationSharingFor(_fromAndTo['from'], _fromAndTo['to'],
                  LocationSharingType.Event, isAccepted, isExited, isSharing);
        }
      } else {
        var _fromAndTo = getFromAndToForEvent(_event);
        SendLocationNotification().allAtsignsLocationData[_atsign] =
            LocationDataModel({
          trimAtsignsFromKey(_event.key!): LocationSharingFor(
              _fromAndTo['from'],
              _fromAndTo['to'],
              LocationSharingType.Event,
              isAccepted,
              isExited,
              isSharing),
        }, null, null, DateTime.now(), currentAtSign!, _atsign);
      }
    }

    await SendLocationNotification()
        .sendLocationAfterDataUpdate(_allAtsignsInEvent);
  }

  /// return from and to for [eventData]
  Map<String, DateTime> getFromAndToForEvent(EventNotificationModel eventData) {
    DateTime? _from;
    DateTime? _to;

    if (compareAtSign(eventData.atsignCreator!,
        AtEventNotificationListener().currentAtSign!)) {
      _from = eventData.event!.startTime;
      _to = eventData.event!.endTime;
    } else {
      late AtContact currentGroupMember;
      // ignore: avoid_function_literals_in_foreach_calls
      eventData.group!.members!.forEach((groupMember) {
        // sending location to other group members
        if (compareAtSign(groupMember.atSign!,
            AtEventNotificationListener().currentAtSign!)) {
          currentGroupMember = groupMember;
        }
      });

      _from = startTimeEnumToTimeOfDay(
              currentGroupMember.tags!['shareFrom'].toString(),
              eventData.event!.startTime) ??
          eventData.event!.startTime;
      _to = endTimeEnumToTimeOfDay(
              currentGroupMember.tags!['shareTo'].toString(),
              eventData.event!.endTime) ??
          eventData.event!.endTime;
    }

    return {
      'from': _from ?? eventData.event!.startTime!,
      'to': _to ?? eventData.event!.endTime!,
    };
  }

  /// updates [haveResponded] property for [notificationModel].
  void updatePendingStatus(EventNotificationModel notificationModel) async {
    for (var i = 0; i < allEventNotifications.length; i++) {
      if (allEventNotifications[i]
          .eventNotificationModel!
          .key!
          .contains(notificationModel.key!)) {
        allEventNotifications[i].haveResponded = true;
      }
    }
  }

  // ignore: missing_return
  /// forms and returns an [AtKey] object based on the given [keyType], [atkeyMicrosecondId], [sharedWith], [sharedBy], and [eventData]
  AtKey? formAtKey(ATKEY_TYPE_ENUM keyType, String atkeyMicrosecondId,
      String? sharedWith, String sharedBy, EventNotificationModel eventData) {
    switch (keyType) {
      case ATKEY_TYPE_ENUM.CREATEEVENT:
        AtKey? atKey;

        // ignore: avoid_function_literals_in_foreach_calls
        allEventNotifications.forEach((event) {
          if (event.eventNotificationModel!.key == eventData.key) {
            atKey = EventService().getAtKey(event.eventNotificationModel!.key!);
          }
        });
        return atKey;

      case ATKEY_TYPE_ENUM.ACKNOWLEDGEEVENT:
        var key = AtKey()
          ..metadata = Metadata()
          ..metadata.ttr = -1
          ..metadata.ccd = true
          ..sharedWith = sharedWith
          ..sharedBy = sharedBy;

        key.key = 'eventacknowledged-$atkeyMicrosecondId';
        return key;
    }
  }

  /// checks if [eventOne] & [eventTwo] have same tags for group members.
  bool compareEvents(
      EventNotificationModel eventOne, EventNotificationModel eventTwo) {
    var isDataSame = true;

    // ignore: avoid_function_literals_in_foreach_calls
    eventOne.group!.members!.forEach((groupOneMember) {
      // ignore: avoid_function_literals_in_foreach_calls
      eventTwo.group!.members!.forEach((groupTwoMember) {
        if (groupOneMember.atSign == groupTwoMember.atSign) {
          if (groupOneMember.tags!['isAccepted'] !=
                  groupTwoMember.tags!['isAccepted'] ||
              groupOneMember.tags!['isSharing'] !=
                  groupTwoMember.tags!['isSharing'] ||
              groupOneMember.tags!['isExited'] !=
                  groupTwoMember.tags!['isExited'] ||
              groupOneMember.tags!['lat'] != groupTwoMember.tags!['lat'] ||
              groupOneMember.tags!['long'] != groupTwoMember.tags!['long']) {
            isDataSame = false;
          }
        }
      });
    });

    return isDataSame;
  }

  /// returns AtValue of [key] if present.
  Future<dynamic> getAtValue(AtKey key) async {
    try {
      var atvalue = await atClientManager.atClient.get(key).catchError(
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

  /// updates listeners
  void notifyListeners() {
    if (streamAlternative != null) {
      streamAlternative!(allEventNotifications);
    }

    EventsMapScreenData().updateEventdataFromList(allEventNotifications);
    atNotificationsSink.add(allEventNotifications);
  }

  /// will calculate [LocationDataModel] for [allEventNotifications] if [listOfEvents] is not provided
  calculateLocationSharingAllEvents(
      {List<EventKeyLocationModel>? listOfEvents,
      bool initLocationSharing = false}) async {
    List<String> atsignToShareLocWith = [];
    List<LocationDataModel> locationToShareWith = [];

    for (var eventKeyLocationModel in (listOfEvents ?? allEventNotifications)) {
      if ((eventKeyLocationModel.eventNotificationModel == null) ||
          (eventKeyLocationModel.eventNotificationModel!.isCancelled == true)) {
        continue;
      }

      var eventNotificationModel =
          eventKeyLocationModel.eventNotificationModel!;

      /// calculate atsigns to share loc with
      atsignToShareLocWith = [];

      if (!compareAtSign(
          eventKeyLocationModel.eventNotificationModel!.atsignCreator!,
          AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
        atsignToShareLocWith
            .add(eventKeyLocationModel.eventNotificationModel!.atsignCreator!);
      }

      if (eventKeyLocationModel
          .eventNotificationModel!.group!.members!.isNotEmpty) {
        Set<AtContact>? groupMembers =
            eventKeyLocationModel.eventNotificationModel!.group!.members!;

        // ignore: avoid_function_literals_in_foreach_calls
        groupMembers.forEach((member) {
          if (!compareAtSign(member.atSign!,
              AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
            atsignToShareLocWith.add(member.atSign!);
          }
        });
      }

      // converting event data to locationDataModel
      locationToShareWith = [
        ...locationToShareWith,
        ...eventNotificationToLocationDataModel(
            eventKeyLocationModel.eventNotificationModel!, atsignToShareLocWith)
      ];
    }

    if (initLocationSharing) {
      SendLocationNotification().initEventData(locationToShareWith);
    } else {
      await Future.forEach(locationToShareWith,
          (LocationDataModel _locationDataModel) async {
        await SendLocationNotification().addMember(_locationDataModel);
      });
    }
  }

  /// will calculate [LocationDataModel] for [eventData]
  calculateLocationSharingForSingleEvent(
      EventNotificationModel eventData) async {
    await calculateLocationSharingAllEvents(listOfEvents: [
      EventKeyLocationModel(eventNotificationModel: eventData)
    ]);
  }

  /// converts [eventData] to [LocationDataModel] for all [atsignList]
  List<LocationDataModel> eventNotificationToLocationDataModel(
      EventNotificationModel eventData, List<String> atsignList) {
    DateTime? _from;
    DateTime? _to;
    late LocationSharingFor locationSharingFor;

    /// calculate DateTime from and to
    if (compareAtSign(eventData.atsignCreator!,
        AtEventNotificationListener().currentAtSign!)) {
      _from = eventData.event!.startTime;
      _to = eventData.event!.endTime;
      locationSharingFor = LocationSharingFor(
          _from,
          _to,
          LocationSharingType.Event,
          !(eventData.isCancelled ?? false),
          eventData.isCancelled ?? false,
          eventData.isSharing ?? false);
    } else {
      late AtContact currentGroupMember;
      // ignore: avoid_function_literals_in_foreach_calls
      eventData.group!.members!.forEach((groupMember) {
        // sending location to other group members
        if (compareAtSign(groupMember.atSign!,
            AtEventNotificationListener().currentAtSign!)) {
          currentGroupMember = groupMember;
        }
      });

      _from = startTimeEnumToTimeOfDay(
              currentGroupMember.tags!['shareFrom'].toString(),
              eventData.event!.startTime) ??
          eventData.event!.startTime;
      _to = endTimeEnumToTimeOfDay(
              currentGroupMember.tags!['shareTo'].toString(),
              eventData.event!.endTime) ??
          eventData.event!.endTime;

      locationSharingFor = LocationSharingFor(
          _from,
          _to,
          LocationSharingType.Event,
          currentGroupMember.tags!['isAccepted'],
          currentGroupMember.tags!['isExited'],
          currentGroupMember.tags!['isSharing']);
    }

    // if (atsignList == null) {
    //   return [locationDataModel];
    // }

    List<LocationDataModel> locationToShareWith = [];
    // ignore: avoid_function_literals_in_foreach_calls
    atsignList.forEach((element) {
      LocationDataModel locationDataModel = LocationDataModel(
        {
          trimAtsignsFromKey(eventData.key!): locationSharingFor,
        },
        null,
        null,
        DateTime.now(),
        AtClientManager.getInstance().atClient.getCurrentAtSign()!,
        element,
      );
      // locationDataModel.receiver = element;
      locationToShareWith.add(locationDataModel);
    });

    return locationToShareWith;
  }

  EventNotificationModel getUpdatedEventData(
      EventNotificationModel originalEvent, EventNotificationModel ackEvent) {
    return originalEvent;
  }

  /// Removes a notification from list
  void removeData(String? key) {
    /// received key Example:
    ///  key: sharelocation-1637059616606602@26juststay
    ///
    if (key == null) {
      return;
    }

    EventNotificationModel? _eventNotificationModel;

    List<String> atsignsToRemove = [];
    allEventNotifications.removeWhere((notification) {
      if (key.contains(
          trimAtsignsFromKey(notification.eventNotificationModel!.key!))) {
        atsignsToRemove =
            getAtsignsFromEvent(notification.eventNotificationModel!);
        _eventNotificationModel = notification.eventNotificationModel;
      }
      return key.contains(
          trimAtsignsFromKey(notification.eventNotificationModel!.key!));
    });

    /// remove from past notifications
    allPastEventNotifications.removeWhere((notification) {
      return key.contains(
          trimAtsignsFromKey(notification.eventNotificationModel!.key!));
    });

    notifyListeners();
    // Remove location sharing
    if (_eventNotificationModel != null)
    // && (compareAtSign(locationNotificationModel.atsignCreator!, currentAtSign!))
    {
      SendLocationNotification().removeMember(key, atsignsToRemove,
          isExited: true, isAccepted: false, isSharing: false);
    }
  }

  /// deletes [_eventNotificationModel] if found
  deleteData(EventNotificationModel _eventNotificationModel) async {
    var key = _eventNotificationModel.key!;
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
}
