import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';

mixin AtClientBindings {
  AtClient get atClient;

  AtSignLogger get logger;

  Future<NotificationResult> notify(
    AtKey atKey,
    String value, {
    required bool checkForFinalDeliveryStatus,
    required bool waitForFinalDeliveryStatus,
    required Duration ttln,

    /// maxTries must be a non-zero positive integer
    int maxTries = 3,
  }) async {
    var params = NotificationParams.forUpdate(
      atKey,
      value: value,
      notificationExpiry: ttln,
    );

    NotificationResult result;

    int attempts = 0;
    do {
      attempts++;
      result = await atClient.notificationService.notify(
        params,
        checkForFinalDeliveryStatus: checkForFinalDeliveryStatus,
        waitForFinalDeliveryStatus: waitForFinalDeliveryStatus,
        onSuccess: (NotificationResult notification) {
          logger.info('SUCCESS:$notification with key: ${atKey.toString()}');
        },
        onError: (notification) {
          logger.info('ERROR:$notification');
        },
      );
    } while (result.atClientException != null && attempts < maxTries);
    if (result.atClientException != null) {
      logger.warning(
          'Failed to send ${atKey.toString()} notification within $maxTries attempts.');
    }
    return result;
  }

  Stream<AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    logger.info('Subscribing to notifications with regex: "$regex"');
    return atClient.notificationService.subscribe(
      regex: regex,
      shouldDecrypt: shouldDecrypt,
    );
  }
}
