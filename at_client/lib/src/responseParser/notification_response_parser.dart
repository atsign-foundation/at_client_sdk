class ResponseParser {
  static NotificationStatusEnum parseNotificationResponse(String status) {
    switch (status) {
      case 'data:delivered':
        return NotificationStatusEnum.delivered;
      default:
        return NotificationStatusEnum.errored;
    }
  }
}

enum NotificationStatusEnum { delivered, errored }
