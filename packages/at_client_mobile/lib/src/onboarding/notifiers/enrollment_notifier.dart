import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/foundation.dart';

enum OnboardingEnrollmentStatus {
  preparing,
  otpRequired,
  validatingOtp,
  pendingApproval,
  success,
  denied,
}

// For implementation in NoPorts see: https://github.com/atsign-foundation/noports/blob/7c3535b4b73ca6ffe6e0f550b0194885ace6edba/packages/dart/npt_flutter/lib/features/onboarding/widgets/onboarding_apkam_dialog.dart#L23

class EnrollmentNotifier extends ChangeNotifier {
  EnrollmentNotifier() : status = OnboardingEnrollmentStatus.preparing;

  late OnboardingEnrollmentStatus status;

  void setStatus(OnboardingEnrollmentStatus newStatus) {
    status = newStatus;
    notifyListeners();
  }

  String? error;
  void setError(String? newError) {
    error = newError;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      final enrollmentStatus = await _getStatus();
      switch (enrollmentStatus) {
        case EnrollmentStatus.pending:
          setStatus(OnboardingEnrollmentStatus.pendingApproval);
          break;
        case EnrollmentStatus.denied:
          setStatus(OnboardingEnrollmentStatus.denied);
          break;
        case EnrollmentStatus.approved:
          setStatus(OnboardingEnrollmentStatus.success);
          break;
        case EnrollmentStatus.revoked:
          setStatus(OnboardingEnrollmentStatus.denied);
          break;
        case EnrollmentStatus.expired:
          setStatus(OnboardingEnrollmentStatus.otpRequired);
          break;
        case null:
          setStatus(OnboardingEnrollmentStatus.otpRequired);
          break;
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> submitOtp(String otp) async {
    try {
      setStatus(OnboardingEnrollmentStatus.validatingOtp);
      await Future.delayed(Duration(seconds: 2));
      setStatus(OnboardingEnrollmentStatus.pendingApproval);
      final success = await _submitOtp(otp);
      if (success) {
        setStatus(OnboardingEnrollmentStatus.success);
      } else {
        setStatus(OnboardingEnrollmentStatus.denied);
      }
    } catch (e) {
      setError(e.toString());
    }
  }

  // TODO: Make a call to auth/onboarding service to get enrollment status.
  Future<EnrollmentStatus?> _getStatus() async {
    await Future.delayed(Duration(seconds: 2));
    return null;
  }

  // TODO: Make a call to auth/onboarding service to submit OTP and await response.
  Future<bool> _submitOtp(String otp) async {
    await Future.delayed(Duration(seconds: 10));
    return true;
  }
}
