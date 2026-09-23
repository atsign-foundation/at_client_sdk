import 'dart:convert';

import 'package:crypto/crypto.dart';

List<int> digestValidatedApiKey(String apiKey) {
  if (apiKey.isEmpty || apiKey.contains(RegExp(r'\s'))) {
    throw ArgumentError.value(
      apiKey.isEmpty ? apiKey : '<redacted>',
      'apiKey',
      'must be non-empty and contain no whitespace',
    );
  }
  return digestApiKey(apiKey);
}

List<int> digestApiKey(String apiKey) {
  return List<int>.unmodifiable(
    sha256.convert(utf8.encode(apiKey)).bytes,
  );
}

bool constantTimeEquals(List<int> first, List<int> second) {
  int difference = first.length ^ second.length;
  final int comparisonLength =
      first.length < second.length ? first.length : second.length;
  for (int index = 0; index < comparisonLength; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

void requireUniqueDigests(List<List<int>> digests) {
  for (int index = 0; index < digests.length; index++) {
    for (int otherIndex = index + 1;
        otherIndex < digests.length;
        otherIndex++) {
      if (constantTimeEquals(digests[index], digests[otherIndex])) {
        throw ArgumentError('API keys must be unique');
      }
    }
  }
}
