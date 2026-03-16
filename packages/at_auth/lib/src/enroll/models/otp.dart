import 'package:meta/meta.dart';

/// A model representing a one-time passcode (OTP) or semi-permanent passcode
/// (SPP) along with its expiry time.
@immutable
class Otp {
  const Otp({
    required this.value,
    required this.expiry,
  }) : assert(value.length == 6, 'OTP must be exactly 6 characters');

  /// Creates an [Otp] with an expiry calculated from [duration] from now.
  Otp.fromDuration({
    required this.value,
    required Duration duration,
  })  : expiry = DateTime.now().add(duration),
        assert(value.length == 6, 'OTP must be exactly 6 characters');

  /// The one-time passcode value.
  final String value;

  /// The time at which this OTP expires.
  final DateTime expiry;

  /// Whether this OTP has expired.
  bool get isExpired => DateTime.now().isAfter(expiry);

  factory Otp.fromJson(Map<String, dynamic> json) {
    return Otp(
      value: json['otp'] as String,
      expiry: DateTime.parse(json['expiry'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'otp': value,
      'expiry': expiry.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Otp && other.value == value && other.expiry == expiry;
  }

  @override
  int get hashCode => value.hashCode ^ expiry.hashCode;

  @override
  String toString() => value;
}
