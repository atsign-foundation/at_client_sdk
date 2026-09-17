import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_commons.dart';

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
