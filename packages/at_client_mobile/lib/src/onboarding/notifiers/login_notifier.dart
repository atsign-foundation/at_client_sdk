import 'package:at_client/at_client.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:flutter/foundation.dart';

enum LoginStatus {
  /// Getting the server status.
  contactingServer,

  /// Fetching keys from the keychain.
  fetchingKeys,

  /// Authenticating with atServer.
  authenticating,

  /// Successfully authenticated with atServer.
  authenticated,

  /// Authenticating with cramSecret.
  cramAuthenticating,

  /// OTP required for authentication.
  otpRequired,

  /// Enrolling with atServer.
  enrollmentRequired,
}

// When onboarding/logging in there are a number states the client and server can be in.
// Server:
// - Teapot -> The server needs to be activated using the registrar API.
// - Activated -> Can be authenticated with existing keys, enrollment or cramSecret.
// - Other -> Some error.
//
// Client:
// - Keys are saved in the keychain -> Authenticate without issues
// - Keys are not saved in the keychain -> If the server is not activated then get CRAM secret with OTP or provided cramSecret.
//                                      -> If the server is activated, then enroll.

class LoginNotifier extends ChangeNotifier {
  LoginNotifier(this.atClientPreference);

  final AtClientPreference atClientPreference;

  LoginStatus _status = LoginStatus.contactingServer;
  LoginStatus get status => _status;

  String? _error;
  String? get error => _error;

  Future<void> login({
    required String atSign,
    String? rootDomain,
    String? cramSecret,
  }) async {
    try {
      _status = LoginStatus.contactingServer;
      _error = null;
      notifyListeners();
      final serverStatus = await _checkServerStatus();
      switch (serverStatus) {
        case AtSignStatus.teapot:
          await _sendActivateCommand();
          _status = LoginStatus.otpRequired;
          notifyListeners();
          return;
        case AtSignStatus.activated:
          _status = LoginStatus.fetchingKeys;
          notifyListeners();

          final hasKeys = await _keysInKeychain();
          if (hasKeys) {
            _status = LoginStatus.authenticating;
            notifyListeners();
            await _authenticate();
            _status = LoginStatus.authenticated;
            notifyListeners();
            return;
          } else if (cramSecret != null && cramSecret.isNotEmpty) {
            await cramAuthenticate(cramSecret, atSign);
            return;
          } else {
            _status = LoginStatus.enrollmentRequired;
            notifyListeners();
            return;
          }
        case AtSignStatus.notFound:
          _error = 'atSign does not exist';
          notifyListeners();
          return;
        default:
          _error = 'Error connecting to atServer';
          notifyListeners();
          return;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> cramAuthenticate(String cramSecret, String atSign) async {
    try {
      _status = LoginStatus.cramAuthenticating;
      _error = null;
      notifyListeners();
      // TODO: Will probably need a retry mechanism while the atServer spins up.
      await _cramAuthenticate(cramSecret, atSign);
      _status = LoginStatus.authenticating;
      notifyListeners();
      await _authenticate();
      _status = LoginStatus.authenticated;
    } catch (e) {
      _error = e.toString();
    } finally {
      notifyListeners();
    }
  }

  // Instead of a String to a file it should be an Atsign defined format (probs in AtChops).
  Future<void> keysAuthenticate(String keysFile) async {
    try {
      _status = LoginStatus.authenticating;
      _error = null;
      notifyListeners();
      // TODO: Extract info from keys file and use that information to authenticate.
      await _authenticate();
      _status = LoginStatus.authenticated;
    } catch (e) {
      _error = e.toString();
    } finally {
      notifyListeners();
    }
  }

  // TODO: Call AtChops to check if keys are in keychain.
  Future<bool> _keysInKeychain() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    return false;
  }

  // TODO: Call OnboardingService to authenticate.
  Future<void> _authenticate() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    throw Exception('Failed to authenticate!');
  }

  // TODO: Call AtUtils to check server status.
  Future<AtSignStatus> _checkServerStatus() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    return AtSignStatus.activated;
  }

  // TODO: Call registrar service to send command to authenticateAtSign.
  Future<void> _sendActivateCommand() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    return;
  }

  // TODO: Call OnboardingService to authenticate with cramSecret.
  Future<void> _cramAuthenticate(String cramSecret, String atSign) async {
    await Future.delayed(const Duration(milliseconds: 2000));
    return;
  }
}
