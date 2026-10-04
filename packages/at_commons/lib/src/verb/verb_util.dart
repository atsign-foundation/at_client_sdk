import 'dart:collection';

class VerbUtil {
  static const String newLineReplacePattern = '~NL~';
  static Iterable<RegExpMatch> _getMatches(RegExp regex, String command) {
    var matches = regex.allMatches(command);
    return matches;
  }

  static HashMap<String, String?> _processMatches(
      Iterable<RegExpMatch> matches) {
    var paramsMap = HashMap<String, String?>();
    for (var f in matches) {
      for (var name in f.groupNames) {
        var namedGroup = f.namedGroup(name);
        if (namedGroup != null) {
          paramsMap.putIfAbsent(name, () => f.namedGroup(name));
        }
      }
    }
    return paramsMap;
  }

  static HashMap<String, String?>? getVerbParam(String regex, String command) {
    var regExp = RegExp(regex);
    var regexMatches = _getMatches(regExp, command);
    if (regexMatches.isEmpty) {
      return null;
    }
    var verbParams = _processMatches(regexMatches);

    return verbParams;
  }

  static String? formatAtSign(String? atSign) {
    if (atSign != null && !atSign.startsWith('@')) {
      atSign = '@$atSign';
    }
    return atSign;
  }

  static String replaceNewline(String value) {
    return value.replaceAll('\n', newLineReplacePattern);
  }

  static String getFormattedValue(String value) {
    return value.replaceAll(newLineReplacePattern, '\n');
  }

  /// Formats [dt] as an ISO 8601 UTC string with exactly six fractional-second
  /// digits, e.g. `2026-05-05T11:59:44.123456Z`. The wire grammar for
  /// timestamp metadata fields (cAt/uAt/eAt/aAt/dAt) accepts this shape;
  /// `DateTime.toIso8601String()` is not used directly because it emits a
  /// variable number of fractional digits depending on whether the source
  /// value carries microseconds.
  static String formatIso8601Micros(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final mo = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final mi = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    final us =
        (utc.millisecond * 1000 + utc.microsecond).toString().padLeft(6, '0');
    return '$y-$mo-${d}T$h:$mi:$s.${us}Z';
  }

  /// The `ttln`, `eAtn` and `eph` fields a notification command carries, in
  /// grammar order.
  ///
  /// Throws [ArgumentError] when [ttln] and [expiresAt] are both set, since two
  /// expiries are ambiguous, or when [ephemeral] comes with a [ttr] or [ccd],
  /// which would make the recipient's atServer persist a cached record.
  static String notificationLifetime(
      {int? ttln,
      DateTime? expiresAt,
      bool ephemeral = false,
      int? ttr,
      bool? ccd}) {
    if (ttln != null && expiresAt != null) {
      throw ArgumentError('a notification carries ttln or eAtn, not both');
    }
    if (ephemeral && (ttr != null || ccd != null)) {
      throw ArgumentError('an ephemeral notification cannot carry ttr or ccd');
    }
    final sb = StringBuffer();
    if (ttln != null) {
      sb.write(':ttln:$ttln');
    }
    if (expiresAt != null) {
      sb.write(':eAtn:${formatIso8601Micros(expiresAt)}');
    }
    if (ephemeral) {
      sb.write(':eph:true');
    }
    return sb.toString();
  }
}
