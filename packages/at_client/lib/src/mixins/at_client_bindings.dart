import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';

mixin AtClientBindings {
  AtClient get atClient;

  AtSignLogger get logger;

  Future<void> notify(
      AtKey atKey,
      String value, {
        required bool checkForFinalDeliveryStatus,
        required bool waitForFinalDeliveryStatus,
        required Duration ttln,
      }) async {
    await atClient.notificationService.notify(
      NotificationParams.forUpdate(atKey,
          value: value, notificationExpiry: ttln),
      checkForFinalDeliveryStatus: checkForFinalDeliveryStatus,
      waitForFinalDeliveryStatus: waitForFinalDeliveryStatus,
      onSuccess: (NotificationResult notification) {
        logger.info('SUCCESS:$notification with key: ${atKey.toString()}');
      },
      onError: (notification) {
        logger.info('ERROR:$notification');
      },
    );
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
