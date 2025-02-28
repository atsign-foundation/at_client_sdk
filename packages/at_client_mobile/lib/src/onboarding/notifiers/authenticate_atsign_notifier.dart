import 'package:flutter/foundation.dart';

class AuthenticateAtsignNotifier extends ChangeNotifier {
  AuthenticateAtsignNotifier();

  // TODO: Pass in RegistrarService.

  String? _cramSecret;
  bool _isFetching = false;
  String? _error;

  String? get cramSecret => _cramSecret;
  bool get isFetching => _isFetching;
  String? get error => _error;

  Future<void> submitOtp({
    required String otp,
    required String atSign,
  }) async {
    try {
      _isFetching = true;
      notifyListeners();
      // TODO: Call registrar service to authenticateAtSignAndActivate.
      await Future.delayed(const Duration(seconds: 2));
      _cramSecret = await Future.value('cram:abcd1234');
    } catch (e) {
      _error = e.toString();
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }
}
