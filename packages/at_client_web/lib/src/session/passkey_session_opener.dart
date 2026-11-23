import 'session_opener.dart';

/// Opens the session of a passkey for [PasskeySessionOptions].
typedef PasskeyLogin = Future<OpenedSession> Function(
    PasskeySessionOptions options);

/// Opens a session on the passkey the browser holds; the stop of what it
/// opens also closes the passkey vault.
class PasskeySessionOpener implements SessionOpener {
  /// [login] is the browser's `passkeyLogin`, as `webPasskeyLogin` adapts it.
  PasskeySessionOpener({required PasskeyLogin login}) : _login = login;

  final PasskeyLogin _login;

  @override
  Future<OpenedSession> open(SessionOptions options) async {
    if (options is! PasskeySessionOptions) {
      throw ArgumentError('is not a passkey session', 'options');
    }
    return await _login(options);
  }
}
