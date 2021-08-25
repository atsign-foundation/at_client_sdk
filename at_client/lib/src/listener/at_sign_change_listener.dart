import 'package:at_client/src/listener/switch_at_sign_event.dart';

abstract class AtSignChangeListener {
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent);
}
