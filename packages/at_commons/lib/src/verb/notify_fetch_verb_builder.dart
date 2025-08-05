import 'package:at_commons/src/exception/at_exceptions.dart';
import 'package:at_commons/src/verb/verb_builder.dart';

/// NotifyFetchVerbBuilder generated the command to fetches the notification
/// with the given notification-id
///
/// ```
/// e.g. To fetch the notification with the notification-id - '21d617cd-fb8a-43e4-98df-7e1536818d59'
///
/// var notifyFetchVerbBuilder = NotifyFetchVerbBuilder()
///                                       ..notificationId = '21d617cd-fb8a-43e4-98df-7e1536818d59';
///
/// Throws InvalidSyntaxException if notification id is not set or initialized to empty string
/// ```
class NotifyFetchVerbBuilder implements VerbBuilder {
  /// Notification Id to fetch the notification
  late String notificationId;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('notify:fetch:');
    try {
      if (notificationId.isEmpty) {
        throw InvalidSyntaxException(
            'Notification-id is empty. Notification-id is mandatory');
      }
    } on Error {
      throw InvalidSyntaxException(
          'Notification-id is not set. Notification-id is mandatory');
    }
    serverCommandBuffer.write('$notificationId\n');
    return serverCommandBuffer.toString();
  }

  @override
  bool checkParams() {
    var isValid = true;
    if (notificationId.isEmpty) {
      isValid = false;
    }
    return isValid;
  }
}
