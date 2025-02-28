import 'package:flutter/widgets.dart';

import '../notifiers/selected_atsign_notifier.dart';

class SelectedAtsignNotifierProvider extends InheritedNotifier<SelectedAtsignNotifier> {
  const SelectedAtsignNotifierProvider({
    required SelectedAtsignNotifier super.notifier,
    required super.child,
    super.key,
  });

  static SelectedAtsignNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SelectedAtsignNotifierProvider>()!.notifier!;
  }
}
