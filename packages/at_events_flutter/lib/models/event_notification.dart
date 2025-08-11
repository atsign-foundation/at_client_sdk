// ignore_for_file: constant_identifier_names, unnecessary_statements

import 'dart:convert';
import 'package:at_contact/at_contact.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

class EventNotificationModel {
  EventNotificationModel();
  String? atsignCreator;
  LatLng? locationOfCreator;
  double? lat;
  double? long;

  bool? isCancelled;
  String? title;
  Venue? venue;
  Event? event;
  String? key;
  AtGroup? group;
  bool? isSharing;
  bool? isUpdate; //when an event data is being updated , this should be true
  EventNotificationModel.fromJson(Map<String, dynamic> data) {
    title = data['title'] ?? '';
    key = data['key'] ?? '';
    atsignCreator = data['atsignCreator'] ?? '';
    isCancelled = data['isCancelled'] == 'true' ? true : false;
    isSharing = data['isSharing'] == 'true' ? true : false;
    isUpdate = data['isUpdate'] == 'true' ? true : false;
    lat = data['lat'] != 'null' && data['lat'] != null
        ? double.parse(data['lat'])
        : null;
    long = data['long'] != 'null' && data['long'] != null
        ? double.parse(data['long'])
        : null;
    if (data['venue'] != null) {
      venue = Venue.fromJson(jsonDecode(data['venue']));
    }
    if (data['event'] != null) {
      event = data['event'] != null
          ? Event.fromJson(jsonDecode(data['event']))
          : null;
    }

    if (data['group'] != null) {
      data['group'] = jsonDecode(data['group']);
      group = AtGroup(data['group']['name']);

      data['group']['members'].forEach((contact) {
        var newContact = AtContact(atSign: contact['atSign']);
        newContact.tags = {};
        newContact.tags!['isAccepted'] = contact['tags']['isAccepted'];
        newContact.tags!['isSharing'] = contact['tags']['isSharing'];
        newContact.tags!['isExited'] = contact['tags']['isExited'];
        newContact.tags!['shareFrom'] = contact['tags']['shareFrom'] != null &&
                contact['tags']['shareFrom'] != 'null'
            ? contact['tags']['shareFrom']
            : -1;
        newContact.tags!['shareTo'] = contact['tags']['shareTo'] != null &&
                contact['tags']['shareTo'] != 'null'
            ? contact['tags']['shareTo']
            : -1;
        newContact.tags!['lat'] =
            contact['tags']['lat'] != null && contact['tags']['lat'] != 'null'
                ? double.parse(contact['tags']['lat'].toString())
                : null;
        newContact.tags!['long'] =
            contact['tags']['long'] != null && contact['tags']['long'] != 'null'
                ? double.parse(contact['tags']['long'].toString())
                : null;
        group!.members!.add(newContact);
      });
    }
  }

  /// converts an EventNotificationModel object to a JSON string representation
  static String convertEventNotificationToJson(
      EventNotificationModel eventNotification) {
    var notification = json.encode({
      'title': eventNotification.title != null
          ? eventNotification.title.toString()
          : '',
      'isCancelled': eventNotification.isCancelled.toString(),
      'isSharing': eventNotification.isSharing.toString(),
      'isUpdate': eventNotification.isUpdate.toString(),
      'atsignCreator': eventNotification.atsignCreator.toString(),
      'key': '${eventNotification.key}',
      'group': json.encode(eventNotification.group),
      'lat': eventNotification.lat.toString(),
      'long': eventNotification.long.toString(),

      /// Update ['group']['updatedAt'] with DateTime.now()
      'venue': json.encode({
        'latitude': eventNotification.venue!.latitude.toString(),
        'longitude': eventNotification.venue!.longitude.toString(),
        'label': eventNotification.venue!.label
      }),
      'event': json.encode({
        'isRecurring': eventNotification.event!.isRecurring.toString(),
        'date': eventNotification.event!.date.toString(),
        'endDate': eventNotification.event!.endDate.toString(),
        'startTime': eventNotification.event!.startTime?.toUtc().toString(),
        'endTime': eventNotification.event!.endTime?.toUtc().toString(),
        'repeatDuration': eventNotification.event!.repeatDuration.toString(),
        'repeatCycle': eventNotification.event!.repeatCycle.toString(),
        'occursOn': eventNotification.event!.occursOn.toString(),
        'endsOn': eventNotification.event!.endsOn.toString(),
        'endEventOnDate': eventNotification.event!.endEventOnDate.toString(),
        'endEventAfterOccurrence':
            eventNotification.event!.endEventAfterOccurance.toString()
      })
    });
    return notification;
  }
}

class Venue {
  Venue();
  double? latitude, longitude;
  String? label;
  Venue.fromJson(Map<String, dynamic> data)
      : latitude =
            data['latitude'] != 'null' ? double.parse(data['latitude']) : 0,
        longitude =
            data['longitude'] != 'null' ? double.parse(data['longitude']) : 0,
        label = data['label'] != 'null' ? data['label'] : '';
}

class Event {
  Event();
  bool? isRecurring;
  DateTime? date, endDate;
  DateTime? startTime, endTime; //one day event
  int? repeatDuration;
  RepeatCycle? repeatCycle;
  Week? occursOn;
  EndsOn? endsOn;
  DateTime? endEventOnDate;
  int? endEventAfterOccurance;
  Event.fromJson(Map<String, dynamic> data) {
    startTime = data['startTime'] != null
        ? DateTime.parse(data['startTime']).toLocal()
        : null;
    endTime = data['endTime'] != null
        ? DateTime.parse(data['endTime']).toLocal()
        : null;
    isRecurring = data['isRecurring'] == 'true' ? true : false;
    if (!isRecurring!) {
      date = data['date'] != 'null' ? DateTime.parse(data['date']) : null;
      endDate =
          data['endDate'] != 'null' ? DateTime.parse(data['endDate']) : null;
    } else {
      repeatDuration = data['repeatDuration'] != 'null'
          ? int.parse(data['repeatDuration'])
          : null;
      repeatCycle = (data['repeatCycle'] == RepeatCycle.WEEK.toString()
          ? RepeatCycle.WEEK
          : (data['repeatCycle'] == RepeatCycle.MONTH.toString()
              ? RepeatCycle.MONTH
              : null));
      switch (repeatCycle) {
        case RepeatCycle.WEEK:
          occursOn = (data['occursOn'] == Week.SUNDAY.toString()
              ? Week.SUNDAY
              : (data['occursOn'] == Week.MONDAY.toString()
                  ? Week.MONDAY
                  : (data['occursOn'] == Week.TUESDAY.toString()
                      ? Week.TUESDAY
                      : (data['occursOn'] == Week.WEDNESDAY.toString()
                          ? Week.WEDNESDAY
                          : (data['occursOn'] == Week.THURSDAY.toString()
                              ? Week.THURSDAY
                              : (data['occursOn'] == Week.FRIDAY.toString()
                                  ? Week.FRIDAY
                                  : (data['occursOn'] ==
                                          Week.SATURDAY.toString()
                                      ? Week.SATURDAY
                                      : null)))))));
          break;
        case RepeatCycle.MONTH:
          date = data['date'] != 'null' ? DateTime.parse(data['date']) : null;
          break;
        default:
          null;
      }
      endsOn = (data['endsOn'] == EndsOn.NEVER.toString()
          ? EndsOn.NEVER
          : (data['endsOn'] == EndsOn.ON.toString()
              ? EndsOn.ON
              : (data['endsOn'] == EndsOn.AFTER.toString()
                  ? EndsOn.AFTER
                  : null)));
      switch (endsOn) {
        case EndsOn.ON:
          endEventOnDate = data['endEventOnDate'] != 'null'
              ? DateTime.parse(data['endEventOnDate'])
              : null;
          break;
        case EndsOn.AFTER:
          endEventAfterOccurance = data['endEventAfterOccurance'] != 'null'
              ? int.parse(data['endEventAfterOccurance'])
              : null;
          break;
        case EndsOn.NEVER:
          break;
        default:
          null;
      }
    }
  }
}

enum RepeatCycle { WEEK, MONTH }

enum Week { SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY }

enum EndsOn { NEVER, ON, AFTER }

/// converts a weekday string to a Week enum value
// ignore: missing_return
Week getWeekEnum(String? weekday) {
  switch (weekday) {
    case 'Monday':
      return Week.MONDAY;
    case 'Tuesday':
      return Week.TUESDAY;
    case 'Wednesday':
      return Week.WEDNESDAY;
    case 'Thursday':
      return Week.THURSDAY;
    case 'Friday':
      return Week.FRIDAY;
    case 'Saturday':
      return Week.SATURDAY;
    case 'Sunday':
      return Week.SUNDAY;
    default:
      return Week.SUNDAY;
  }
}

/// converts a Week enum value to a weekday string
// ignore: missing_return
String getWeekString(Week? weekday) {
  switch (weekday) {
    case Week.MONDAY:
      return 'Monday';
    case Week.TUESDAY:
      return 'Tuesday';
    case Week.WEDNESDAY:
      return 'Wednesday';
    case Week.THURSDAY:
      return 'Thursday';
    case Week.FRIDAY:
      return 'Friday';
    case Week.SATURDAY:
      return 'Saturday';
    case Week.SUNDAY:
      return 'Sunday';
    default:
      return 'Sunday';
  }
}

/// converts a DateTime object to a formatted time string
String timeOfDayToString(DateTime time) {
  var minute = time.minute;
  if (minute < 10) return '${time.hour}: 0${time.minute}';

  return '${time.hour}: ${time.minute}';
}

/// converts a DateTime object to a formatted date string
String dateToString(DateTime date) {
  var dateString = '${date.month}/${date.day}/${date.year}';

  return dateString;
}

/// list of repeat occurrence options
List<String> get repeatOccuranceOptions => ['Week', 'Month'];

/// list of options for the day of the week
List<String> get occursOnWeekOptions => [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];

// ignore: camel_case_types
enum ATKEY_TYPE_ENUM { CREATEEVENT, ACKNOWLEDGEEVENT }

/// mapping of months with their respective properties
Map<String, dynamic> get monthsList => {
      '1': {'month': 'jan', 'days': 31, 'count': 1},
      '2': {'month': 'feb', 'days': 28, 'count': 2},
      '3': {'month': 'mar', 'days': 31, 'count': 3},
      '4': {'month': 'apr', 'days': 30, 'count': 4},
      '5': {'month': 'may', 'days': 31, 'count': 5},
      '6': {'month': 'jun', 'days': 30, 'count': 6},
      '7': {'month': 'jul', 'days': 31, 'count': 7},
      '8': {'month': 'aug', 'days': 31, 'count': 8},
      '9': {'month': 'sept', 'days': 30, 'count': 9},
      '10': {'month': 'oct', 'days': 31, 'count': 10},
      '11': {'month': 'nov', 'days': 30, 'count': 11},
      '12': {'month': 'dec', 'days': 31, 'count': 12},
    };

class EventInfo {
  late bool isAccepted, isSharing, isExited;
  DateTime? from;

  EventInfo({
    required this.isSharing,
    required this.isExited,
    required this.isAccepted,
    this.from,
  });
}
