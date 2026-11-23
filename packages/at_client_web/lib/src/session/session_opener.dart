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
/// here, once; no other layer parses or checks it.
sealed class SessionOptions {
  SessionOptions._(
      {required String atSign, required String namespace, String? rootDomain})
      : atSign = _atSign(atSign),
        namespace = _namespace(namespace),
        rootDomain = _rootDomain(rootDomain);

  /// The atSign, in `@name` form.
  final String atSign;

  /// The client's namespace, folded to lower case; it is also the app name of
  /// the enrollment.
  final String namespace;

  /// The atDirectory to look atSigns up at, or null for the production one.
  final AtRootDomain? rootDomain;

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
}

/// A session on a decoded `.atKeys` document.
final class KeysSessionOptions extends SessionOptions {
  /// Throws an [ArgumentError] naming `keys` after the shared fields when
  /// [keys] is not a usable `.atKeys` document.
  KeysSessionOptions(
      {required super.atSign,
      required super.namespace,
      required Map<String, dynamic> keys,
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

/// A client that is open, and how to end whatever opened it.
class OpenedSession {
  /// [stop] defaults to stopping [client]; a session that holds more than
  /// the client, such as a passkey vault, gives the stop that releases it
  /// too.
  OpenedSession(this.client, {Future<void> Function()? stop})
      : stop = stop ?? client.stop;

  final AtClient client;

  /// Ends the session: stops the client and releases what the opener holds.
  final Future<void> Function() stop;
}

/// Opens a session for [SessionOptions] of the kind it takes.
abstract interface class SessionOpener {
  /// Throws an [ArgumentError] naming `options` for a kind it does not take.
  Future<OpenedSession> open(SessionOptions options);
}

/// Sends each kind of [SessionOptions] to the opener that takes it.
class RoutingSessionOpener implements SessionOpener {
  RoutingSessionOpener({required this.keys, required this.passkey});

  final SessionOpener keys;
  final SessionOpener passkey;

  @override
  Future<OpenedSession> open(SessionOptions options) => switch (options) {
        KeysSessionOptions() => keys.open(options),
        PasskeySessionOptions() => passkey.open(options),
      };
}

/// Opens a session with [opener] and hands it to [wrap]. When [wrap] throws,
/// the opened session is stopped and [wrap]'s own error is the one thrown,
/// whether or not the stop succeeds.
Future<T> openWrapped<T>(SessionOpener opener, SessionOptions options,
    T Function(OpenedSession opened) wrap) async {
  final opened = await opener.open(options);
  try {
    return wrap(opened);
  } on Object {
    try {
      await opened.stop();
    } on Object {
      // The wrap error is the one the caller needs.
    }
    rethrow;
  }
}
