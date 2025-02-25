import 'package:flutter/foundation.dart';

class RegisterPersonNotifier extends ChangeNotifier {
  RegisterPersonNotifier();

  // TODO: Pass in RegistrarService.

  bool _isFetching = false;
  String? _error;

  bool get isFetching => _isFetching;
  String? get error => _error;

  Future<void> registerPerson(String email, String atSign) async {
    try {
      _isFetching = true;
      notifyListeners();
      // await _atAuthService.registerPerson(email, atSign);
      await Future.delayed(const Duration(seconds: 2));
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }
}
