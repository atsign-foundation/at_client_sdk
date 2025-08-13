import 'event_notification.dart';

/// Model containing the [eventNotificationModel] associated with the event.
class EventKeyLocationModel {
  EventNotificationModel? eventNotificationModel;
  bool haveResponded;
  EventKeyLocationModel(
      {this.eventNotificationModel, this.haveResponded = false});
}
