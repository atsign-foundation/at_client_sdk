bool hasRegexMatch(String key, String regex) {
  return RegExp(regex).hasMatch(key);
}