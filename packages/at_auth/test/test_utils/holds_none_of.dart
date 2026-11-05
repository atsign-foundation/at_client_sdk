import 'package:test/test.dart';

/// Matches an object whose text holds no run of [window] consecutive
/// characters of [value], so a quoted slice of it fails as surely as the
/// whole of it.
Matcher holdsNoneOf(String value, {int window = 8}) {
  if (value.length < window) {
    throw ArgumentError.value(
        value, 'value', 'shorter than the $window-character window');
  }
  return predicate<Object?>((actual) {
    final text = '$actual';
    for (var i = 0; i + window <= value.length; i++) {
      if (text.contains(value.substring(i, i + window))) return false;
    }
    return true;
  }, 'text holding no $window-character run of the value');
}
