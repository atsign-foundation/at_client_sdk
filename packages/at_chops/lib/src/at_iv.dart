import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/secure_random.dart';

class InitialisationVector {
  late Uint8List ivBytes;
  InitialisationVector(this.ivBytes);

  static InitialisationVector random(int length) =>
      InitialisationVector(secureRandomBytes(length));

  @Deprecated('use .random() in favour')
  static InitialisationVector legacy() => InitialisationVector(Uint8List(16));

  static InitialisationVector fromBase64(String ivBase64) =>
      InitialisationVector(base64Decode(ivBase64));
}
