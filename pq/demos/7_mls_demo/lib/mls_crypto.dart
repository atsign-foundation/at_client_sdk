import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart';

// RFC 9420 §7.2 ExpandWithLabel
Uint8List expandWithLabel(HmacSha256 hmac, Uint8List secret, String label, Uint8List context, int length) {
  // hkdfLabel = length(u16 big-endian) || "MLS 1.0 " || label || context
  final labelBytes = Uint8List.fromList('MLS 1.0 $label'.codeUnits);
  final buf = BytesBuilder();
  buf.addByte((length >> 8) & 0xff);
  buf.addByte(length & 0xff);
  buf.addByte(labelBytes.length);  // label length byte
  buf.add(labelBytes);
  buf.addByte(context.length);  // context length byte (single byte since context ≤ 255 B in our use)
  buf.add(context);
  final info = buf.takeBytes();
  // HKDF-Expand single block (L≤32): T(1) = HMAC-SHA256(PRK=secret, info || 0x01)
  final T1input = Uint8List(info.length + 1);
  T1input.setAll(0, info);
  T1input[info.length] = 0x01;
  final t1 = hmac.mac(secret, T1input);
  return t1.sublist(0, length);
}

// RFC 9420 §7.2 DeriveSecret
Uint8List deriveSecret(HmacSha256 hmac, Uint8List secret, String label) {
  return expandWithLabel(hmac, secret, label, Uint8List(0), 32);
}

// HKDF-Extract(salt, ikm) = HMAC-SHA256(key=salt, data=ikm)
Uint8List hkdfExtract(HmacSha256 hmac, Uint8List salt, Uint8List ikm) {
  return hmac.mac(salt, ikm);
}
