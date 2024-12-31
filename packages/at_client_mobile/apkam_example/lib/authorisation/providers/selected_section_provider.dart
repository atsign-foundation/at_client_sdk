import 'package:flutter/widgets.dart';

import '../pages/authorisation_page_section.dart';

class SelectedSection extends ChangeNotifier {
  SelectedSection({required AuthorisationPageSection initialSection}) : _selectedSection = initialSection;

  AuthorisationPageSection _selectedSection;

  AuthorisationPageSection get selectedSection => _selectedSection;

  void updateSelectedSection(AuthorisationPageSection section) {
    _selectedSection = section;
    notifyListeners();
  }
}

class SelectedSectionProvider extends InheritedNotifier<SelectedSection> {
  const SelectedSectionProvider({
    required SelectedSection super.notifier,
    required super.child,
    super.key,
  });

  static SelectedSection of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SelectedSectionProvider>()!.notifier!;
  }
}
