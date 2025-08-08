import 'package:at_commons/at_commons.dart';

class AtMetadataUtil {
  static final AtMetadataUtil _singleton = AtMetadataUtil._internal();

  factory AtMetadataUtil() {
    return _singleton;
  }

  AtMetadataUtil._internal();

  /// Accepts a string which represents the MillisecondsSinceEpoch
  /// Returns [ttlMs] which is time_to_live in MilliSecondsSinceEpoch
  /// Method ensures [ttl] has a valid value
  static int validateTTL(String? ttl) {
    int ttlMs = 0;
    if (ttl == null || ttl.trim().isEmpty) {
      return ttlMs;
    }
    try {
      ttlMs = int.parse(ttl);
    } on FormatException {
      throw InvalidSyntaxException(
          'Valid value for TTL should be greater than or equal to 0');
    }
    // TTL cannot have a negative value.
    if (ttlMs < 0) {
      throw InvalidSyntaxException(
          'Valid value for TTL should be greater than or equal to 0');
    }
    return ttlMs;
  }

  /// Accepts a string which represents the MillisecondsSinceEpoch
  /// Returns [ttlMs] which is time_to_birth in MilliSecondsSinceEpoch
  /// Method ensures [ttb] has a valid value
  static int validateTTB(String? ttb) {
    int ttbMs = 0;
    if (ttb == null || ttb.trim().isEmpty) {
      return ttbMs;
    }
    try {
      ttbMs = int.parse(ttb);
    } on FormatException {
      throw InvalidSyntaxException(
          'Valid value for TTB should be greater than or equal to 0');
    }
    // TTB cannot have a negative value.
    if (ttbMs < 0) {
      throw InvalidSyntaxException(
          'Valid value for TTB should be greater than or equal to 0');
    }
    return ttbMs;
  }

  static int? validateTTR(int? ttrMs) {
    if (ttrMs == null || ttrMs == 0) {
      return null;
    }
    if (ttrMs <= -2) {
      throw InvalidSyntaxException(
          'Valid values for TTR are -1 and greater than or equal to 1');
    }
    return ttrMs;
  }

  /// Throws [InvalidSyntaxException] if ttr is 0 or null.
  static bool? validateCascadeDelete(int? ttr, bool? isCascade) {
    // When ttr is 0 or null, key is not cached, hence setting isCascade to null.
    if (ttr == 0 || ttr == null) {
      return null;
    }
    isCascade ??= false;
    return isCascade;
  }

  static bool getBoolVerbParams(String? arg1) {
    if (arg1 != null) {
      if (arg1.toLowerCase() == 'true') {
        return true;
      }
    }
    return false;
  }
}
