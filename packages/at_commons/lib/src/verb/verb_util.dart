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
}
