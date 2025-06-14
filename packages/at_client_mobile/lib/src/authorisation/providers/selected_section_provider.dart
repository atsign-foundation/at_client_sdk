import 'package:flutter/widgets.dart';

import '../notifiers/selected_section_notifier.dart';

class SelectedSectionProvider
    extends InheritedNotifier<SelectedSectionNotifier> {
  const SelectedSectionProvider({
    required SelectedSectionNotifier super.notifier,
    required super.child,
    super.key,
  });

  static SelectedSectionNotifier of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SelectedSectionProvider>()!
        .notifier!;
  }
}
