import 'package:at_client/at_client.dart';

class SwitchAtSignEvent {
  AtClient? previousAtClient;
  late AtClient newAtClient;
  SwitchAtSignEvent(this.previousAtClient, this.newAtClient) {
    if (previousAtClient == newAtClient) {
      throw IllegalArgumentException(
          'previousAtClient may not be the same as newAtClient');
    }
  }
}
