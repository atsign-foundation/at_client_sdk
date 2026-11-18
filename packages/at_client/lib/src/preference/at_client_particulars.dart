import 'package:uuid/uuid.dart';

/// What a client tells its atServer about the app it runs in, set on
/// `AtClientPreference.atClientParticulars`.
class AtClientParticulars {
  final String _clientId = Uuid().v4();

  /// A unique identifier to distinguish clients on the server logs.
  String get clientId => _clientId.hashCode.toString();

  /// The app's name, sent on every `from:` the client sends to authenticate.
  /// Unset or blank, the name of the program file is sent instead, or
  /// "unknown" where there is none.
  String? appName;

  /// The app's version, sent on every `from:` the client sends to
  /// authenticate. Unset or blank, "unknown" is sent instead.
  String? appVersion;

  /// The platform on which the app is running on.
  String? platform;
}
