import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:at_chops/src/util/at_chops_util.dart';
import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for AtChopsUtil', () {
    test('Test generate randomIV length', () {
      var iv = AtChopsUtil.generateRandomIV(16);
      expect(iv.ivBytes.length, 16);
    });

    test('Test generate randomIV - two different IVs', () {
      var iv1 = AtChopsUtil.generateRandomIV(16);
      var iv2 = AtChopsUtil.generateRandomIV(16);
      expect(IV(iv1.ivBytes).base64 != IV(iv2.ivBytes).base64, true);
    });

    test('Test generate legacy IV length', () {
      var iv = AtChopsUtil.generateIVLegacy();
      expect(iv.ivBytes.length, 16);
    });
    test('Test generate legacy IV value', () {
      var iv = AtChopsUtil.generateIVLegacy();
      List<int> allZeroesList = [];
      for (int i = 0; i < 16; i++) {
        allZeroesList.add(0);
      }

      expect(ListEquality().equals(iv.ivBytes, allZeroesList), true);
    });

    test('Test generate IV from base64String', () {
      var random = Random();
      List<int> randomBytes =
          List<int>.generate(16, (i) => random.nextInt(256));
      var iv =
          AtChopsUtil.generateIVFromBase64String(base64.encode(randomBytes));
      expect(ListEquality().equals(iv.ivBytes, randomBytes), true);
    });
  });
}
