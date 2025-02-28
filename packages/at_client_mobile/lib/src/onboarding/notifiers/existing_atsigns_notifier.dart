import 'package:flutter/foundation.dart';

class ExistingAtSignsNotifier extends ChangeNotifier {
  ExistingAtSignsNotifier();

  Map<String, String> _existingAtSigns = {};
  bool _isFetching = false;
  String? _error;

  /// A map of existing atSigns and their corresponding domains.
  Map<String, String> get existingAtSigns => Map.unmodifiable(_existingAtSigns);
  bool get isFetching => _isFetching;
  String? get error => _error;

  Future<void> fetchExistingAtSigns() async {
    try {
      _isFetching = true;
      notifyListeners();
      // TODO: Fetch existing Atsigns from the keychain.
    } catch (e) {
      _error = e.toString();
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }
}
