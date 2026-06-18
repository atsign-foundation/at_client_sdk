import 'dart:convert';
import 'dart:math';

import 'package:at_chops/src/util/at_chops_util.dart';
import 'package:collection/collection 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for AtChopsUtil', () {
    test('Test generate randomIV length', () {
      var iv = InitialisationVector.random(16);
      expect(iv.ivBytes.length, 16);
    });

    test('Test generate randomIV - two different IVs', () {
      var iv1 = InitialisationVector.random(16);
      var iv2 = InitialisationVector.random(16);
      expect(IV(iv1.ivBytes).base64 != IV(iv2.ivBytes).base64, true);
    });

    test('Test generate legacy IV length', () {
      var iv = InitialisationVector.legacy();
      expect(iv.ivBytes.length, 16);
    });
    test('Test generate legacy IV value', () {
      var iv = InitialisationVector.legacy();
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
          InitialisationVector.fromBase64(base64.encode(randomBytes));
      expect(ListEquality().equals(iv.ivBytes, randomBytes), true);
    });
  });
}
