import 'session_opener.dart';

/// Opens a session on the passkey the browser holds; the stop of what it
/// opens also closes the passkey vault.
class PasskeySessionOpener implements SessionOpener {
  /// [login] is the browser's `passkeyLogin`, as `webPasskeyLogin` adapts it.
  PasskeySessionOpener(
      {required Future<OpenedSession> Function(PasskeySessionOptions options)
          login})
      : _login = login;

  final Future<OpenedSession> Function(PasskeySessionOptions options) _login;

  @override
  Future<OpenedSession> open(SessionOptions options) async {
    if (options is! PasskeySessionOptions) {
      throw ArgumentError('is not a passkey session', 'options');
    }
    return await _login(options);
  }
}
