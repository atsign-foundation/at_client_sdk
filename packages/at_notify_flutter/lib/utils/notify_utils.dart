import 'package:at_notify_flutter/models/notify_model.dart';
import 'package:at_notify_flutter/services/notify_service.dart';
import 'package:flutter/material.dart';

enum NotifyEnum {
  notifyForUpdate,
  notifyForDelete,
  notifyText,
}

/// Notification handling service
NotifyService _notifyService = NotifyService();

/// Notify Text
Future<bool> notifyText(
  BuildContext context,
  String? atSign,
  String? sendToAtSign,
  String? message,
) async {
  var _res = await _notifyService.sendNotify(
      sendToAtSign!,
      Notify(
        time: DateTime.now().millisecondsSinceEpoch,
        atSign: atSign,
        message: message,
      ),
      NotifyEnum.notifyText);
  return _res;
}
