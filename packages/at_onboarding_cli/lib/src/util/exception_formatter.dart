/// Utility class for formatting exception messages
class ExceptionMessageFormatter {
  /// Extracts a clean error message from potentially nested exceptions.
  /// Removes redundant "Exception: " prefixes and extracts the root cause.
  ///
  /// Example:
  /// Input: "Exception: Onboarding failed : Exception: Unable to write keys..."
  /// Output: "Unable to write keys..."
  static String extractRootCause(dynamic error) {
    String errorStr = error.toString();

    // Remove redundant "Exception: " prefixes
    errorStr = errorStr.replaceAll(RegExp(r'Exception:\s*'), '');

    // Pattern: "wrapping context : actual error"
    // Extract the part after the last " : " to get the root cause
    final lastColonIndex = errorStr.lastIndexOf(' : ');
    if (lastColonIndex != -1) {
      errorStr = errorStr.substring(lastColonIndex + 3);
    }

    // Remove any leading/trailing whitespace
    return errorStr.trim();
  }
}