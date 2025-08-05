part of dart_utf7;

/// Implements the encode and decode functionality
class Utf7 {
  // set D (directly encoded characters): A-Za-z0-9'()´-./:?
  // set O (optional direct characters): !"#$%&*;<=>@[]^_`{|}
  // set B (base64 characters): base64, but without =

  /// Checks if the given [char] is part of set D (directly encoded characters)
  static bool _isInStrictSet(int char) {
    if (char < 39 || char > 122) return false;
    if ((65 <= char && char <= 90 /* A-Z */) ||
        (97 <= char && char <= 122 /* a-z */) ||
        (44 <= char && char <= 58) /* 0-9 and ´-./: */ ||
        (39 <= char && char <= 41 /* '() */) ||
        char == 63 /* ? */) return true;
    return false; // any other character in between
  }

  /// Checks if the given [char] is part of set O *OR D*
  static bool _isInLooseSet(int char) {
    if (char == 10 || char == 13 || char == 9) return true;
    if (char < 32 || char > 125 || char == 92 || char == 43) return false;
    return true;
  }

  /// Encodes the given [string] with the modified base64 algorithm defined in
  /// rfc 2152
  static String encodeModifiedBase64(String string) {
    var out = <int>[];
    for (var i = 0; i < string.length; i++) {
      out.add(string.codeUnitAt(i) >> 8);
      out.add(string.codeUnitAt(i) & 0xFF);
    }
    return base64Encode(out).replaceAll('=', '');
  }

  /// decodes the given [modifiedBase64] string to standard utf-16 text
  static String decodeModifiedBase64(String modifiedBase64) {
    var bytes = base64Decode(base64.normalize(modifiedBase64));
    var buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i = i + 2) {
      buffer.writeCharCode(bytes[i] << 8 | bytes[i + 1]);
    }
    return buffer.toString();
  }

  /// Encodes [string] to utf-7. Only characters not in the [setTest] are
  /// encoded.
  static String _encode(String string, bool Function(int char) setTest) {
    var buffer = StringBuffer();
    var index = 0;
    var char, shiftStart=null;
    void encodeShifted(bool inclusiveEnd) {
      buffer.writeCharCode(43); // +
      buffer.write(
          Utf7.encodeModifiedBase64(string.substring(shiftStart, index)));
      buffer.writeCharCode(45); // -
      shiftStart = null;
    }

    while (index < string.length) {
      char = string.codeUnitAt(index);
      if (char == 43 /* + */) {
        if (shiftStart != null) encodeShifted(false);
        buffer.write('+-');
      } else if (setTest(char)) {
        if (shiftStart != null) encodeShifted(false);
        buffer.writeCharCode(char);
      } else {
        shiftStart ??= index;
      }
      index++;
    }
    if (shiftStart != null) encodeShifted(true);
    return buffer.toString();
  }

  /// Encodes the utf-8 [string] to the corresponding utf-7 string, also encodes
  /// optional direct characters
  ///
  /// Should be used if the utf-7 string is used at a place where those
  /// characters have a special meaning.
  static String encodeAll(String string) {
    return _encode(string, _isInStrictSet);
  }

  /// Encodes the utf-8 [string] to the corresponding utf-7 string.
  ///
  /// Does not encode "set O" characters, [encodeAll] should be used if used
  /// in a place where those characters have special meaning.
  static String encode(String string) {
    return _encode(string, _isInLooseSet);
  }

  /// Decodes the utf-7 [string] to the corresponding utf-8 string.
  static String decode(String string) {
    return string.replaceAllMapped(RegExp(r'\+([A-Za-z0-9/+]*)-?'),
        (Match match) {
      if (match[1]!.isEmpty) return '+';
      return decodeModifiedBase64(match[1]!);
    });
  }
}
