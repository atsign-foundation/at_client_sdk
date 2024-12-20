import 'package:flutter/foundation.dart';

/// {@template otp}
/// A model representing a one-time passcode (OTP) with an expiry time.
/// {@endtemplate}
@immutable
class Otp {
  /// {@macro otp}
  Otp({
    required this.otp,
    required this.expiry,
  })  : assert(otp.length >= 6, 'OTP should be 6 or more characters'),
        assert(expiry.isAfter(DateTime.now()));

  /// Creates an [Otp] object with a specified duration from now.
  Otp.fromDuration({
    required this.otp,
    required Duration duration,
  })  : expiry = DateTime.now().add(duration),
        assert(otp.length >= 6, 'OTP should be 6 or more characters');

  /// The one-time passcode.
  final String otp;

  /// The expiry time of the OTP.
  final DateTime expiry;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Otp && other.otp == otp && other.expiry == expiry;
  }

  @override
  int get hashCode => otp.hashCode ^ expiry.hashCode;

  @override
  String toString() {
    return otp;
  }
}
