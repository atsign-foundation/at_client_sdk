// Copyright (c) 2015, Rick Zhou. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library base2e15.test;

import 'dart:convert';

import 'package:base2e15/base2e15.dart';
//import 'dart:math';

bool testEqual(Object a, Object b, String testName) {
  if (a == b) {
    print('$testName Passed!');
    return true;
  } else {
    print('$testName Failed, "$a" != "$b"');
    return false;
  }
}
main() {
  String msg = 'Base2e15 is awesome!';
  String encoded = Base2e15.encode(utf8.encode(msg));
  testEqual(encoded, '嗺둽嬖蟝巍媖疌켉溁닽壪', 'Encoding Test');
  String decoded = utf8.decode(Base2e15.decode(encoded));
  testEqual(decoded, msg, 'Decoding Test');
  String encoded2 = '~嗺둽嬖蟝巍媖疌123켉溁닽壪';
  String decoded2 = utf8.decode(Base2e15.decode(encoded2));
  testEqual(decoded2, msg, 'Malformed Decoding Test');

//  Random rng = new Random();
//  List bytes = new List(100);
//  for (int i = 0; i < 10000; ++i) {
//    int k = 50 + rng.nextInt(50);
//    for (int j = 0; j < k; ++j) {
//      bytes[j] = rng.nextInt(256);
//    }
//    String encoded = Base2e15.encode(bytes.sublist(0,k));
//    List newbytes = Base2e15.decode(encoded);
//    for (int j = 0; j < k; ++j) {
//      if (bytes[j] != newbytes[j]) {
//        print('Failed:$bytes');
//        print('      :$newbytes');
//        break;
//      }
//    }
//  }
}
