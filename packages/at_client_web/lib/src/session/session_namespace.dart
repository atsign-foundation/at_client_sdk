import 'package:at_client/at_client.dart' show Regexes;

import '../exceptions.dart';

final _sessionNamespacePattern = RegExp('^${Regexes.charsInNamespace}\$');

/// Returns [namespace] folded to lower case, or throws an [InvalidArgumentException]
/// naming `namespace` without its value when it is empty or invalid.
String normalizeSessionNamespace(String namespace) {
  if (!_sessionNamespacePattern.hasMatch(namespace)) {
    throw InvalidArgumentException(
        'namespace must be a non-empty valid segment');
  }
  return namespace.toLowerCase();
}
