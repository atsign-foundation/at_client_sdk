// Copyright (c) 2015, Rick Zhou. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// The base2e15 library.
/// Map 15 bits to unicode
/// 0x0000 ~ 0x1935 -> U+3480 ~ U+4DB5   CJK Unified Ideographs Extension A
/// 0x1936 ~ 0x545B -> U+4E00 ~ U+8925   CJK Unified Ideographs
/// 0x545C ~ 0x7FFF -> U+AC00 ~ U+D7A3   Hangul Syllables
/// 7 bits special case, only used by last character
///  0x00  ~  0x7F  -> U+3400 ~ U+347F   CJK Unified Ideographs Extension A
library base2e15;
import 'dart:typed_data';
class Base2e15 {

  static String encode(List<int> bytes, [int lineSize = 0, String? linePadding]) {
    List<int?> charCodes = encodeToCharCode(bytes);
    if (lineSize <= 0) {
      return new String.fromCharCodes(charCodes as Iterable<int>);
    }
    List rslt = [];
    int len = charCodes.length;
    for (int i = 0; i < len; i += lineSize) {
      int j = i + lineSize;
      if (j < len) {
        j = len;
      }
      if (linePadding != null) {
        rslt.add('$linePadding${new String.fromCharCodes(charCodes.sublist(i, j) as Iterable<int>)}');
      } else {
        rslt.add(new String.fromCharCodes(charCodes.sublist(i, j) as Iterable<int>));
      }
    }
    return rslt.join('\n');
  }

  static List<int?> encodeToCharCode(List<int> bytes) {
    int bn = 15; // bit needed
    int bv = 0; // bit value
    int outLen = (bytes.length * 8 + 14) ~/ 15;
    List<int> out = new List<int>.filled(outLen, -1, growable: false);
    int pos = 0;
    for (int byte in bytes) {
      if (bn > 8) {
        bv = (bv << 8) | byte;
        bn -= 8;
      } else {
        bv = ((bv << bn) | (byte >> (8 - bn))) & 0x7FFF;
        if (bv < 0x1936) {
          out[pos++] = bv + 0x3480;
        } else if (bv < 0x545C) {
          out[pos++] = bv + 0x34CA;
        } else {
          out[pos++] = bv + 0x57A4;
        }
        bv = byte;
        bn += 7;
      }
    }
    if (bn != 15) {
      if (bn > 7) { // need 8 bits or more, so has 7 bits or less
        out[pos++] = ((bv << (bn - 8)) & 0x7F) + 0x3400;
      } else {
        bv = (bv << bn) & 0x7FFF;
        if (bv < 0x1936) {
          out[pos++] = bv + 0x3480;
        } else if (bv < 0x545C) {
          out[pos++] = bv + 0x34CA;
        } else {
          out[pos++] = bv + 0x57A4;
        }
      }
    }
    return out;
  }

  static Uint8List decode(String input) {
    int bn = 8; // bit needed
    int bv = 0; // bit value
    int maxLen = (input.length * 15 + 7) ~/ 8;
    Uint8List out = new Uint8List(maxLen);
    int pos = 0;
    int cv;
    for (int code in input.codeUnits) {
      if (code > 0x33FF && code < 0xD7A4) {
        if (code > 0xABFF) {
          cv = code - 0x57A4;
        } else if (code > 0x8925) {
          continue; // invalid range
        } else if (code > 0x4DFF) {
          cv = code - 0x34CA;
        } else if (code > 0x4DB5) {
          continue; // invalid range
        } else if (code > 0x347F) {
          cv = code - 0x3480;
        } else {
          cv = code - 0x3400;
          out[pos++] = (bv << bn) | (cv >> (7 - bn));
          break; // last 8 bit data received, break
        }
        out[pos++] = (bv << bn) | (cv >> (15 - bn));
        bv = cv;
        bn -= 7;
        if (bn < 1) {
          out[pos++] = bv >> -bn;
          bn += 8;
        }
      }
    }
    return out.sublist(0, pos);
  }
}
