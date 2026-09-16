import 'package:at_client/at_client.dart';
import 'package:duration/duration.dart';

/// A one-time passcode from [atClient]'s atSign for an enrollment request to
/// quote; [otpExpiry], spelled as a duration such as `10m`, bounds its life,
/// and with none the atServer's default applies.
Future<String> requestEnrollmentOtp(AtClient atClient,
    {String? otpExpiry}) async {
  final passcode = await atClient.enrollments.otp(
      expiry: otpExpiry == null || otpExpiry.isEmpty
          ? null
          : parseDuration(otpExpiry));
  return passcode.value;
}
