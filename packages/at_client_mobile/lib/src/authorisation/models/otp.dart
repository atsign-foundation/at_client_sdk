import 'package:flutter/foundation.dart';

/// {@template otp}
/// A model representing a one-time passcode (OTP) with an expiry time.
/// {@endtemplate}
@immutable
class Otp {
  /// {@macro otp}
  const Otp({
    required this.value,
    required this.expiry,
  }) : assert(value.length >= 6, 'OTP should be 6 or more characters');

  /// Creates an [Otp] object with a specified duration from now.
  Otp.fromDuration({
    required this.value,
    required Duration duration,
  })  : expiry = DateTime.now().add(duration),
        assert(value.length >= 6, 'OTP should be 6 or more characters');

  /// The one-time passcode.
  final String value;

  /// The expiry time of the OTP.
  final DateTime expiry;

  /// Creates an [Otp] object from a JSON map.
  factory Otp.fromJson(Map<String, dynamic> json) {
    return Otp(
      value: json['otp'] as String,
      expiry: DateTime.parse(json['expiry'] as String),
    );
  }

  /// Converts the [Otp] object to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'otp': value,
      'expiry': expiry.toIso8601String(),
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiry);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Otp && other.value == value && other.expiry == expiry;
  }

  @override
  int get hashCode => value.hashCode ^ expiry.hashCode;

  @override
  String toString() {
    return value;
  }
}
