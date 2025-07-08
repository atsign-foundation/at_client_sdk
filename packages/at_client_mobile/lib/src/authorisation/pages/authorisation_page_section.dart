import 'package:flutter/material.dart';

/// The different sections of the authorisation page.
enum AuthorisationPageSection {
  /// The OTP section.
  otp,

  /// The set pin section.
  /// Shows the current pin (if present) and allows the user to set a new pin.
  setPin,

  /// The requests section.
  /// Shows current pending requests.
  requests,

  /// The approved enrollments section.
  /// Shows just the approved enrollments.
  approvedEnrollments,

  /// The history section.
  /// Shows the entire history of the user's authorisation requests.
  history,
}

extension AuthorisationPageSectionX on AuthorisationPageSection {
  /// The name of the section.
  /// [BuildContext] is required to get the localized string.
  String title(BuildContext context) {
    switch (this) {
      case AuthorisationPageSection.otp:
        return 'OTP';
      case AuthorisationPageSection.setPin:
        return 'Set pin';
      case AuthorisationPageSection.requests:
        return 'Requests';
      case AuthorisationPageSection.approvedEnrollments:
        return 'Approved Enrollments';
      case AuthorisationPageSection.history:
        return 'History';
    }
  }

  IconData get icon {
    switch (this) {
      case AuthorisationPageSection.otp:
        return Icons.numbers;
      case AuthorisationPageSection.setPin:
        return Icons.dialpad;
      case AuthorisationPageSection.requests:
        return Icons.question_mark_outlined;
      case AuthorisationPageSection.approvedEnrollments:
        return Icons.done_all;
      case AuthorisationPageSection.history:
        return Icons.history;
    }
  }
}
