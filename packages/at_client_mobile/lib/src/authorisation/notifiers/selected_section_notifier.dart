import 'package:flutter/widgets.dart';

import '../pages/authorisation_page_section.dart';

class SelectedSectionNotifier extends ChangeNotifier {
  SelectedSectionNotifier({required AuthorisationPageSection initialSection})
      : _selectedSection = initialSection;

  AuthorisationPageSection _selectedSection;

  AuthorisationPageSection get selectedSection => _selectedSection;

  void updateSelectedSection(AuthorisationPageSection section) {
    _selectedSection = section;
    notifyListeners();
  }
}
