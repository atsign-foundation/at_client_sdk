import 'dart:typed_data';

/// Returns [cipherText] followed by [tag] in one [Uint8List] of exactly their
/// combined length, copying each once.
Uint8List cipherTextThenTag(List<int> cipherText, List<int> tag) =>
    Uint8List(cipherText.length + tag.length)
      ..setRange(0, cipherText.length, cipherText)
      ..setRange(cipherText.length, cipherText.length + tag.length, tag);
