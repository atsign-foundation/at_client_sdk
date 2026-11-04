import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

class InitialisationVector {
  late Uint8List ivBytes;
  InitialisationVector(this.ivBytes);

  static InitialisationVector random(int length) {
    final iv = IV.fromSecureRandom(length);
    return InitialisationVector(iv.bytes);
  }

  static InitialisationVector legacy() {
    return InitialisationVector(IV(Uint8List(16)).bytes);
  }

  static InitialisationVector fromBase64(String ivBase64) {
    final iv = IV.fromBase64(ivBase64);
    return InitialisationVector(iv.bytes);
  }
}
