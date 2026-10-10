/// Lowercase hex encoding of [bytes], two characters per byte.
///
/// Internal: the string form the hashing algorithms report. Digest APIs hand
/// back raw bytes, and the Atsign Protocol carries hashes as lowercase hex
/// (checksums, `md5CheckSum`), so there is one encoder rather than one per algo.
String hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
