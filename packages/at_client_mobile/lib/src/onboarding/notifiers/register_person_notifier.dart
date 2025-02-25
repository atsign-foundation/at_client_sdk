import 'package:flutter/foundation.dart';

class RegisterPersonNotifier extends ChangeNotifier {
  RegisterPersonNotifier();

  // TODO: Pass in RegistrarService.

  String? _email;
  bool _isFetching = false;
  String? _error;

  bool get isFetching => _isFetching;
  String? get error => _error;
  String? get email => _email;

  Future<void> registerPerson(String email, String atSign) async {
    try {
      _isFetching = true;
      notifyListeners();
      await Future.delayed(const Duration(seconds: 2));
      _email = email;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _email = null;
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }
}
