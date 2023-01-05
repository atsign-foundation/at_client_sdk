import 'package:at_client/src/listener/switch_at_sign_event.dart';

abstract class AtSignChangeListener {
  /// Indicates if the listener is active or not.
  /// The flag is set to true when the listener is instantiated
  /// When switching between the atSign's, the previous atSign listeners are
  /// marked as inactive and cleared from the list
  late bool isActive;

  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent);
}
