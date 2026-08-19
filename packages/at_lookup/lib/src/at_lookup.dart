import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

/// Performs one authentication on a connection that is already open, using
/// [executor] to speak to the atServer, and returns whether it succeeded.
///
/// This is the whole of authentication reduced to one value. at_lookup cannot
/// name `AtKeys` or `AtKeysIo` - they live in at_auth, which depends on
/// at_lookup - so the credential, the enrollment and the signing algorithm all
/// stay on the at_auth side of this typedef and none of them reach here.
///
/// Implementations are invoked once per connection that needs authenticating,
/// so a closure held for an instance's life must decide afresh each time what
/// credential applies: an instance that CRAM-onboards and then PKAM-
/// authenticates is one instance and two answers.
typedef AtAuthenticator = Future<bool> Function(AtCommandExecutor executor);

/// The narrow view of a connection that an [AtAuthenticator] is given: enough
/// to run a challenge-response, and nothing else.
abstract interface class AtCommandExecutor {
  /// Sends [command] and returns the atServer's reply.
  ///
  /// "Sync" names the channel, not the Dart semantics: verb responses are the
  /// synchronous side of the connection, the side where a reply belongs to the
  /// command that preceded it. Notifications are the asynchronous side and
  /// never arrive here.
  ///
  /// Called from inside authentication, which already holds the
  /// request/response mutex, so this must not take it again.
  Future<String> sendSync(String command);
}

abstract interface class AtLookUp {
  /// update
  Future<bool> update(String key, String value,
      {String? sharedWith, Metadata? metadata});

  /// lookup
  Future<String> lookup(String key, String sharedBy,
      {bool auth = true, bool verifyData = false});

  /// plookup
  Future<String> plookup(String key, String sharedBy);

  Future<String> llookup(String key,
      {String? sharedBy, String? sharedWith, bool isPublic = false});

  /// delete
  Future<bool> delete(String key, {String? sharedWith, bool isPublic = false});

  /// scan
  Future<List<String>> scan({String? regex, String? sharedBy});

  Future<String?> executeVerb(VerbBuilder builder, {bool sync = false});

  Future<String?> executeCommand(String command, {bool auth = false});

  /// Performs a PKAM authentication using private key on the client side and public key on secondary server
  ///
  /// Pkam private key should be set in  [atChops.atChopsKeys]
  ///
  /// Default signing algorithm for pkam signature is [SigningAlgoType.rsa2048] and default hashing algorithm is [HashingAlgoType.sha256]
  ///
  /// Optionally pass enrollmentId if the client is enrolled using APKAM
  Future<bool> pkamAuthenticate({String? enrollmentId});

  /// Generates digest using from verb response and [secret] and performs a
  /// CRAM authentication to secondary server
  Future<bool> cramAuthenticate(String secret);

  /// Terminates the underlying connection to the atServer
  /// used by this instance of AtLookup
  Future<void> close();

  /// set an instance of  [AtChops] for signing and verification operations.
  set atChops(AtChops? atChops);

  OutboundConnection? get connection;

  AtChops? get atChops;

  set secondaryAddressFinder(SecondaryAddressFinder secondaryAddressFinder);

  SecondaryAddressFinder get secondaryAddressFinder;

  /// Signing algorithm for pkam signature
  set signingAlgoType(SigningAlgoType signingAlgoType);

  SigningAlgoType get signingAlgoType;

  /// Hashing algorithm for pkam signature
  set hashingAlgoType(HashingAlgoType hashingAlgoType);

  HashingAlgoType get hashingAlgoType;

  /// EnrollmentId has to be set for clients that are enrolled through APKAM.
  set enrollmentId(String? enrollmentId);

  String? get enrollmentId;
}
