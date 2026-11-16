/// LookUpUtil class
class LookUpUtil {
  /// Returns List contains domain and port.
  ///
  /// The port follows the last `:`, so a bracketed IPv6 literal such as
  /// `[::1]:8443` keeps its brackets and gives `[::1]` and `8443`, and `[::1]`
  /// alone, with no port, gives nothing.
  static List<String> getSecondaryInfo(String url) {
    var result = <String>[];
    final separator = url.lastIndexOf(':');
    // NOTE: a colon before the closing bracket is inside an IPv6 literal.
    if (separator != -1 && separator > url.lastIndexOf(']')) {
      result.add(url.substring(0, separator));
      result.add(url.substring(separator + 1));
    }
    return result;
  }
}
