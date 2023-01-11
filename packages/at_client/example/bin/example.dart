import 'package:at_client/at_client.dart';

/// The example below demonstrates on initializing the [AtClientManager]
/// and getting [AtClient] and [NotificationService] instances.
void main() async {
  final atSign = '@alice🛠';
  final namespace = '.wavi';
  final atClientPreference = AtClientPreference();
  // Initializing AtClientManager instance
  await AtClientManager.getInstance()
      .setCurrentAtSign(atSign, namespace, atClientPreference);

  // Getting the AtClient instance
  AtClient atClient = AtClientManager.getInstance().atClient;
  // Storing value to keystore
  atClient.put(
      AtKey.public('phone', namespace: namespace).build(), '+91 8908901234');

  // Invoking the notify method
  atClient.notificationService.notify(NotificationParams.forUpdate(
      AtKey.shared('phone', namespace: namespace).build()));
}
