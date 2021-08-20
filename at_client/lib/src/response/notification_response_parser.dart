import 'dart:convert';

import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/notification_service_impl.dart';

class NotificationResponseParser extends DefaultResponseParser {

  @override
  Response parse(String responseString) {
    return super.parse(responseString);
  }

  List<AtNotification> getAtNotifications(Response response) {
    final notificationList = <AtNotification>[];
    if (response.isError) {
      return [];
    }
    final notificationJson = response.response;
    var notifications = notificationJson.split('notification: ');
    notifications.forEach((notification) {
      if (notification.isEmpty) {
        return;
      }
      notification = notification.replaceFirst('notification:', '');
      notification = notification.trim();
      final atNotification = AtNotification.fromJson(jsonDecode(notification));
      notificationList.add(atNotification);
    });
    return notificationList;
  }
}
