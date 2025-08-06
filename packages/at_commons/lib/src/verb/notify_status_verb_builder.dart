import 'package:at_commons/src/exception/at_exceptions.dart';
import 'package:at_commons/src/utils/string_utils.dart';
import 'package:at_commons/src/verb/verb_builder.dart';

class NotifyStatusVerbBuilder implements VerbBuilder {
  /// Notification Id to query the status of notification
  String? notificationId;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('notify:status:');
    if (notificationId.isNullOrEmpty) {
      throw InvalidAtKeyException('NotificationId cannot be null or empty');
    }
    serverCommandBuffer.write('$notificationId\n');
    return serverCommandBuffer.toString();
  }

  @override
  bool checkParams() {
    return notificationId.isNotNullOrEmpty;
  }
}
