import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/authorisation_service.dart';

class ActiveOtpNotifier extends ChangeNotifier {
  ActiveOtpNotifier(this.service) {
    generateOtp();
  }

  final AuthorisationService service;

  Otp? _data;
  bool _isFetching = false;
  String? _error;

  Otp? get otp => _data;
  bool get isFetching => _isFetching;
  String? get error => _error;

  /// Fetches the OTP from the service.
  /// If [refresh] is true, the OTP will be fetched even if it already exists.
  Future<void> generateOtp({
    bool refresh = false,
  }) async {
    if (refresh) {
      _data = null;
      _error = null;
    }
    if (_data != null) {
      return;
    }
    _isFetching = true;
    notifyListeners();

    try {
      final otp = await service.generateOtp();
      _data = otp;
    } catch (e) {
      _data = null;
      _error = e.toString();
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }
}
