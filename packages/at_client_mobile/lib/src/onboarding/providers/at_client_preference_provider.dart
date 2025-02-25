import 'package:at_client/at_client.dart';
import 'package:flutter/widgets.dart';

class AtClientPreferenceProvider extends InheritedWidget {
  const AtClientPreferenceProvider({
    required this.preferences,
    required super.child,
    super.key,
  });

  final AtClientPreference preferences;

  static AtClientPreference of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AtClientPreferenceProvider>()!.preferences;
  }

  @override
  bool updateShouldNotify(AtClientPreferenceProvider oldWidget) {
    return oldWidget.preferences != preferences;
  }
}
