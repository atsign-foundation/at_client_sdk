import 'package:at_client/at_client.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_group_flutter/at_contacts_group_flutter.dart';
import 'package:at_events_flutter/at_events_flutter.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/services/at_event_notification_listener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtClient extends Mock implements AtClient {
  @override
  Future<bool> put(AtKey key, dynamic value,
      {bool isDedicated = false, putRequestOptions}) async {
    return true;
  }

  @override
  Future<bool> delete(AtKey key,
      {bool isDedicated = false,
      DeleteRequestOptions? deleteRequestOptions}) async {
    return true;
  }

  @override
  Future<List<String>> getKeys(
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool showHiddenKeys = false}) async {
    return ["@83apedistinct", "@45expected"];
  }

  @override
  Future<AtValue> get(
    AtKey key, {
    bool isDedicated = false,
    GetRequestOptions? getRequestOptions,
  }) async {
    return AtValue();
  }

  @override
  String? getCurrentAtSign() {
    return "@83apedistinct";
  }
}

class MockAtClientManager with Mock implements AtClientManager {
  @override
  AtClient get atClient => MockAtClient();
}

void main() {
  EventNotificationModel model = EventNotificationModel();
  AtGroup group = AtGroup("group");
  Venue venue = Venue();
  venue.latitude = 20.8;
  venue.longitude = 20.8;
  venue.label = "label";
  Event event = Event();
  event.isRecurring = false;
  event.date = DateTime.parse("2024-02-27");
  event.endDate = DateTime.parse("2024-03-27");
  event.startTime = DateTime.parse("2024-02-27");
  event.endTime = DateTime.parse("2024-03-27");
  event.repeatDuration = 1;
  event.repeatCycle = RepeatCycle.MONTH;
  event.endsOn = EndsOn.ON;
  event.endEventOnDate = DateTime.parse("2024-03-27");
  event.endEventAfterOccurance = 1;
  group.members = {AtContact(atSign: "@83apedistinct")};
  model.group = group;
  model.key = "xyz-@83apedistinct-createevent-@45expected";
  model.venue = venue;
  model.event = event;
  model.title = "title";

  // const channel = MethodChannel('at_events_flutter');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {});

  tearDown(() {});

  test("create_event", () async {
    EventService().eventNotificationModel = model;
    EventService().isEventUpdate = true;
    EventService().atClientManager = MockAtClientManager();

    var res = await EventService().createEvent();
    expect(res, true);
  });

  test("edit_event", () async {
    EventService().eventNotificationModel = model;
    EventService().atClientManager = MockAtClientManager();

    var res = await EventService().editEvent();
    expect(res, true);
  });

  test("add_new_group_members", () async {
    EventService().eventNotificationModel = model;

    await EventService()
        .addNewGroupMembers([AtContact(atSign: "@83apedistinct")]);
    expect(EventService().selectedContactsAtSigns.length, 1);
  });

  test("add_new_contact_and_group_members", () async {
    EventService().eventNotificationModel = model;

    GroupContactsModel groupContactsModel = GroupContactsModel().copyWith(
      contact: AtContact(atSign: "@83apedistinct"),
      group: group,
      contactType: ContactsType.CONTACT,
    );

    await EventService().addNewContactAndGroupMembers([groupContactsModel]);
    expect(EventService().selectedContactsAtSigns.length, 1);
  });

  test("add_contacts_to_list", () async {
    EventService().eventNotificationModel = model;

    EventService().addContactToList(AtContact(atSign: "@83apedistinct"));
    expect(EventService().selectedContactsAtSigns.length, 1);
  });

  test("create_contact_list_from_group_memebers", () async {
    EventService().eventNotificationModel = model;

    EventService().createContactListFromGroupMembers();
    expect(EventService().selectedContactsAtSigns.length, 1);
  });

  test("get_group_member_contact", () async {
    EventService().eventNotificationModel = model;

    var res = EventService()
        .getGroupMemberContact(AtContact(atSign: "@83apedistinct"));
    expect(res, isA<AtContact>());
  });

  test("is_event_time_slot_overlap", () async {
    EventService().eventNotificationModel = model;

    var res = EventService().isEventTimeSlotOverlap([model], model);
    expect(res[0], true);
  });

  test("create_event_form_validation", () async {
    EventService().eventNotificationModel = model;

    var res = EventService().createEventFormValidation();
    expect(res, true);
  });

  test("check_for_one_day_event_form_validation", () async {
    EventService().eventNotificationModel = model;

    var res = EventService().checForOneDayEventFormValidation(model);
    expect(res, true);
  });

  test("check_for_recurring_day_event_form_validation", () async {
    EventService().eventNotificationModel = model;

    var res = EventService().checForRecurringeDayEventFormValidation(model);
    expect(res, null);
  });

  test("remove_selected_contact", () async {
    EventService().eventNotificationModel = model;

    EventService().selectedContacts = [AtContact(atSign: "@83apedistinct")];
    EventService().selectedContactsAtSigns = ["@83apedistinct"];

    EventService().removeSelectedContact(0);
    expect(EventService().selectedContactsAtSigns.length, 0);
  });

  // key

  test("filter_past_events_from_list", () async {
    EventKeyLocationModel eventKeyLocationModel = EventKeyLocationModel();
    eventKeyLocationModel.eventNotificationModel = model;
    eventKeyLocationModel.haveResponded = true;
    EventKeyStreamService().allEventNotifications = [eventKeyLocationModel];

    model.event?.endTime = DateTime.parse("2021-03-27");

    EventKeyStreamService().filterPastEventsFromList();
    expect(EventKeyStreamService().allEventNotifications.length, 0);
  });

  test("add_data_to_list", () async {
    model.event?.endTime = DateTime.parse("2024-03-27");
    model.atsignCreator = "@83apedistinct";
    EventKeyStreamService().currentAtSign = "@45expected";

    var res = await EventKeyStreamService().addDataToList(model);
    expect(res, isA<EventKeyLocationModel>());
  });

  test("check_for_pending_events", () async {
    EventKeyLocationModel eventKeyLocationModel = EventKeyLocationModel();
    eventKeyLocationModel.eventNotificationModel = model;
    eventKeyLocationModel.haveResponded = false;
    EventKeyStreamService().allEventNotifications = [eventKeyLocationModel];
    EventKeyStreamService().currentAtSign = "@83apedistinct";
    EventKeyStreamService().atClientManager = MockAtClientManager();

    Map<dynamic, dynamic> tags = {
      "isAccepted": false,
      "isExited": false,
    };

    // model.event?.endTime = DateTime.parse("2021-03-27");
    group.members = {AtContact(atSign: "@83apedistinct", tags: tags)};

    await EventKeyStreamService().checkForPendingEvents();
    expect(eventKeyLocationModel.haveResponded, true);
  });

  test("is_past_notification", () async {
    model.event?.endTime = DateTime.parse("2021-03-27");

    var res = EventKeyStreamService().isPastNotification(model);
    expect(res, true);
  });

  test("is_event_shared_with_me", () {
    EventKeyLocationModel eventKeyLocationModel = EventKeyLocationModel();
    eventKeyLocationModel.eventNotificationModel = model;
    eventKeyLocationModel.haveResponded = false;
    EventKeyStreamService().allEventNotifications = [eventKeyLocationModel];
    var res = EventKeyStreamService().isEventSharedWithMe(model);
    expect(res, true);
  });

  test("get_from_and_to_from_event", () {
    Map<dynamic, dynamic> tags = {
      "shareFrom": "@83apedistinct",
      "shareTo": "@45expected",
    };
    model.atsignCreator = "@83apedistinct";
    group.members = {AtContact(atSign: "@83apedistinct", tags: tags)};

    AtEventNotificationListener().currentAtSign = "@83apedistinct";

    var res = EventKeyStreamService().getFromAndToForEvent(model);
    expect(res, isA<Map<String, DateTime>>());
  });

  test("update_pending_status", () {
    EventKeyLocationModel eventKeyLocationModel = EventKeyLocationModel();
    eventKeyLocationModel.eventNotificationModel = model;
    eventKeyLocationModel.haveResponded = false;
    EventKeyStreamService().allEventNotifications = [eventKeyLocationModel];

    EventKeyStreamService().updatePendingStatus(model);
    expect(
        EventKeyStreamService().allEventNotifications[0].haveResponded, true);
  });

  test("form_at_key", () {
    EventKeyLocationModel eventKeyLocationModel = EventKeyLocationModel();
    eventKeyLocationModel.eventNotificationModel = model;
    eventKeyLocationModel.haveResponded = false;
    EventKeyStreamService().allEventNotifications = [eventKeyLocationModel];

    var res = EventKeyStreamService().formAtKey(ATKEY_TYPE_ENUM.CREATEEVENT,
        "id", "@45expected", "@82apedistinct", model);
    expect(res, isA<AtKey>());
  });

  test("compare_events", () {
    Map<dynamic, dynamic> tags = {
      "isAccepted": true,
      "isSharing": true,
      "isExited": true,
      "lat": 1.0,
      "long": 1.0,
    };
    group.members = {AtContact(atSign: "@83apedistinct", tags: tags)};

    var res = EventKeyStreamService().compareEvents(model, model);
    expect(res, true);
  });

  test("get_at_value", () async {
    EventKeyStreamService().atClientManager = MockAtClientManager();

    AtKey key = AtKey();
    key.key = "xyz-@83apedistinct-createevent-@45expected";
    key.sharedBy = "@83apedistinct";
    key.sharedWith = "@45expected";

    var res = await EventKeyStreamService().getAtValue(key);
    expect(res, isA<AtValue>());
  });
}
