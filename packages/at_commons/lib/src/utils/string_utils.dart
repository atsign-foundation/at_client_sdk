/// Extending the String class to check null and empty.
extension NullOrEmptyCheck on String? {
  _isNullOrEmpty() {
    if (this == null || this!.isEmpty) {
      return true;
    }
    return false;
  }

  bool get isNullOrEmpty => _isNullOrEmpty();

  bool get isNotNullOrEmpty => !_isNullOrEmpty();
}
