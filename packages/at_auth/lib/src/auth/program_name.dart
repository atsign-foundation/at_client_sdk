/// What a clientConfig value is when there is nothing to name.
const String unknownClientConfigValue = 'unknown';

/// The name of the program file [script] returns: its basename cut at the
/// first '.', so a pub snapshot named `at_activate.dart-3.14.0.snapshot` is
/// `at_activate`.
///
/// "unknown" when [script] throws, is not a `file:` URI, or leaves nothing
/// before the first '.'. Never any part of the path but the basename.
String programNameOf(Uri Function() script) {
  final Uri uri;
  try {
    uri = script();
  } catch (_) {
    return unknownClientConfigValue;
  }
  if (uri.scheme != 'file' || uri.pathSegments.isEmpty) {
    return unknownClientConfigValue;
  }
  final basename = uri.pathSegments.last;
  final dot = basename.indexOf('.');
  final name = dot < 0 ? basename : basename.substring(0, dot);
  return name.isEmpty ? unknownClientConfigValue : name;
}
