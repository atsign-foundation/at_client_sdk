import 'package:at_client/at_client.dart' show Regexes;

import '../exceptions.dart';

final _sessionNamespacePattern = RegExp('^${Regexes.charsInNamespace}\$');

/// [namespace] folded to lower case; the one place a namespace is folded.
String foldNamespace(String namespace) => namespace.toLowerCase();

/// Returns [namespace] folded to lower case, or throws an [InvalidArgumentException]
/// for `namespace` when it is empty or invalid.
String normalizeSessionNamespace(String namespace) {
  if (!_sessionNamespacePattern.hasMatch(namespace)) {
    throw InvalidArgumentException('namespace');
  }
  return foldNamespace(namespace);
}
