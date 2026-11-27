import 'package:at_client/at_client.dart';

import '../exceptions.dart';
import 'session_namespace.dart';
import 'session_transport_options.dart';

/// What a caller says about the session it wants, in one of two forms: the
/// `.atKeys` document ([KeysSessionOptions]) or a passkey
/// ([PasskeySessionOptions]).
///
/// A constructor validates every field before anything is opened and throws
/// an [ArgumentError] naming the field, never carrying its value; it checks
/// in the order atSign, namespace, rootDomain, then the form's own fields.
/// The root domain is given as the text `host` or `host:port` and parsed
/// here, before anything is opened; no other layer parses or checks it.
sealed class SessionOptions {
  SessionOptions._(
      {required String atSign,
      required String namespace,
      String? rootDomain,
      String? appName,
      String? appVersion})
      : atSign = _atSign(atSign),
        namespace = _namespace(namespace),
        rootDomain = _rootDomain(rootDomain),
        appName = _label(appName),
        appVersion = _label(appVersion);

  /// The atSign, in `@name` form.
  final String atSign;

  /// The client's namespace, folded to lower case; it is also the app name of
  /// the enrollment.
  final String namespace;

  /// The atDirectory to look atSigns up at, or null for the production one.
  final AtRootDomain? rootDomain;

  /// The app's name to tell the atServer, trimmed; null when absent or blank.
  /// It is a label, not an identity: the atSign still comes from the keys.
  final String? appName;

  /// The app's version to tell the atServer, trimmed; null when absent or
  /// blank.
  final String? appVersion;

  /// Checks the shared fields in order, for a form that must check its own
  /// fields after them but before this constructor runs.
  static void _checkShared(String atSign, String namespace, String? root) {
    _atSign(atSign);
    _namespace(namespace);
    _rootDomain(root);
  }

  static String _atSign(String raw) {
    try {
      return Atsign(raw);
    } on InvalidAtSignException {
      throw ArgumentError('is not a valid atSign', 'atSign');
    }
  }

  static String _namespace(String raw) {
    try {
      return normalizeSessionNamespace(raw);
    } on InvalidArgumentException {
      throw ArgumentError('is not a valid namespace segment', 'namespace');
    }
  }

  static AtRootDomain? _rootDomain(String? raw) {
    if (raw == null) return null;
    final AtRootDomain root;
    try {
      root = AtRootDomain.parse(raw);
      SessionTransportOptions(root: root);
    } on Object {
      throw ArgumentError('is not a valid root domain', 'rootDomain');
    }
    return root;
  }

  static String? _label(String? raw) {
    final trimmed = raw?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// A session on a decoded `.atKeys` document.
final class KeysSessionOptions extends SessionOptions {
  /// Throws an [ArgumentError] naming `keys` after the shared fields when
  /// [keys] is not a usable `.atKeys` document.
  KeysSessionOptions(
      {required super.atSign,
      required super.namespace,
      required Map<String, dynamic> keys,
      super.appName,
      super.appVersion,
      super.rootDomain})
      : keys = _keys(atSign, namespace, rootDomain, keys),
        super._();

  /// The decoded document.
  final AtKeys keys;

  static AtKeys _keys(String atSign, String namespace, String? root,
      Map<String, dynamic> document) {
    SessionOptions._checkShared(atSign, namespace, root);
    try {
      return AtKeys.fromJson(document);
    } on Object {
      throw ArgumentError('is not a usable .atKeys document', 'keys');
    }
  }
}

/// A session on the passkey the browser holds for the atSign.
final class PasskeySessionOptions extends SessionOptions {
  /// Throws an [ArgumentError] naming `rpId` or `rpName` when it is empty.
  PasskeySessionOptions(
      {required super.atSign,
      required super.namespace,
      required this.rpId,
      required this.rpName,
      super.appName,
      super.appVersion,
      super.rootDomain})
      : super._() {
    if (rpId.trim().isEmpty) throw ArgumentError('must not be empty', 'rpId');
    if (rpName.trim().isEmpty) {
      throw ArgumentError('must not be empty', 'rpName');
    }
  }

  /// The relying party id the passkey is bound to.
  final String rpId;

  /// The relying party's display name.
  final String rpName;
}
