import 'package:at_auth/at_auth.dart';
import 'package:at_client_mobile/src/auth/at_auth_service.dart';
import 'package:flutter/foundation.dart';

class CramAuthenticationNotifier extends ChangeNotifier {
  CramAuthenticationNotifier(this._atAuthService);

  final AtAuthService _atAuthService;

  bool _isFetching = false;
  String? _error;

  bool get isFetching => _isFetching;
  String? get error => _error;

  Future<void> authenticate(String atSign, String cramSecret) async {
    try {
      _isFetching = true;
      notifyListeners();
      final onboardingRequest = AtOnboardingRequest(atSign);
      await _atAuthService.onboard(onboardingRequest, cramSecret: cramSecret);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }
}
