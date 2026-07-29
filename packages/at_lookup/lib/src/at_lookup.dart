import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

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
  /// [pkamSigner] must be set — it signs the `from` challenge and declares the
  /// signing/hashing algorithm (defaults to rsa2048/sha256).
  ///
  /// If [pkamSigner] is null but the deprecated [atChops] is set, signing falls
  /// back to [atChops] using [signingAlgoType] / [hashingAlgoType].
  ///
  /// Optionally pass enrollmentId if the client is enrolled using APKAM
  Future<bool> pkamAuthenticate({String? enrollmentId});

  /// Generates digest using from verb response and [secret] and performs a
  /// CRAM authentication to secondary server
  Future<bool> cramAuthenticate(String secret);

  /// Terminates the underlying connection to the atServer
  /// used by this instance of AtLookup
  Future<void> close();

  /// The strategy used to sign the PKAM `from` challenge. Set by the consumer
  /// (at_auth), which owns the key material and picks the signing algorithm.
  ///
  /// Takes precedence over the deprecated [atChops] when both are set.
  set pkamSigner(AtPkamSigner? pkamSigner);

  AtPkamSigner? get pkamSigner;

  OutboundConnection? get connection;

  /// set an instance of [AtChops] for signing and verification operations.
  @Deprecated('Use pkamSigner — at_lookup no longer needs the key material,'
      ' only something that can sign the pkam challenge')
  set atChops(AtChops? atChops);

  @Deprecated('Use pkamSigner')
  AtChops? get atChops;

  /// Signing algorithm for pkam signature
  @Deprecated('Use pkamSigner — AtPkamSigner.signingAlgo declares the'
      ' algorithm it signs with')
  set signingAlgoType(SigningAlgoType signingAlgoType);

  @Deprecated('Use pkamSigner.signingAlgo')
  SigningAlgoType get signingAlgoType;

  /// Hashing algorithm for pkam signature
  @Deprecated('Use pkamSigner — AtPkamSigner.hashingAlgo declares the hashing'
      ' algorithm it signs with')
  set hashingAlgoType(HashingAlgoType hashingAlgoType);

  @Deprecated('Use pkamSigner.hashingAlgo')
  HashingAlgoType get hashingAlgoType;

  set secondaryAddressFinder(SecondaryAddressFinder secondaryAddressFinder);

  SecondaryAddressFinder get secondaryAddressFinder;

  /// EnrollmentId has to be set for clients that are enrolled through APKAM.
  set enrollmentId(String? enrollmentId);

  String? get enrollmentId;
}
