import 'package:apkam_example/authorisation/models/models.dart';
import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:flutter/widgets.dart';

class ActiveOtp extends ChangeNotifier {
  ActiveOtp(this.service) {
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

class ActiveOtpProvider extends InheritedNotifier<ActiveOtp> {
  const ActiveOtpProvider({
    required ActiveOtp super.notifier,
    required super.child,
    super.key,
  });

  static ActiveOtp of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ActiveOtpProvider>()!.notifier!;
  }
}
