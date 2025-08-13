import 'location_notification.dart';

/// Model containing the [locationNotificationModel], [haveResponded].
class KeyLocationModel {
  LocationNotificationModel? locationNotificationModel;
  bool? haveResponded;

  KeyLocationModel(
      {this.locationNotificationModel, this.haveResponded = false});
}
