import 'package:at_client/at_client.dart';

/// A client for one atSign, opened from the keyfile the preference names and
/// made the manager's current client.
///
/// The rest of an atSign's lifecycle is at_client's: `Atsign.activate`
/// activates an atSign, `Atsign.enroll` and `PendingEnrollment` enrol a
/// device, `client.enrollments` manages the roster and its passcodes, and
/// `client.connection` says whether the atServer can be reached.
abstract class AtOnboardingService {
  /// Opens the client for this atSign from the keyfile at
  /// `AtOnboardingPreference.atKeysFilePath`, makes it
  /// `AtClientManager.getInstance().atClient`, and answers whether its
  /// connection is online.
  ///
  /// False means the client opened but is not online; its `connection` says
  /// whether the atServer was unreachable or refused it. A refusal on a
  /// device that has never held this atSign online opens nothing, and
  /// [atClient] stays null. Any client already live for the atSign in this
  /// process is stopped first, this call's earlier one included, and a fresh
  /// one opened.
  Future<bool> authenticate();

  /// The client the last [authenticate] opened, or null before one has.
  AtClient? get atClient;

  @Deprecated('use atClient')
  Future<AtClient?> getAtClient();
}
