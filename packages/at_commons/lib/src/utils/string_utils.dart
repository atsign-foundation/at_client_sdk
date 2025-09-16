/// Extending the String class to check null and empty.
extension NullOrEmptyCheck on String? {
  bool _isNullOrEmpty() {
    return (this == null || this!.isEmpty);
  }

  bool get isNullOrEmpty => _isNullOrEmpty();

  bool get isNotNullOrEmpty => !_isNullOrEmpty();
}
