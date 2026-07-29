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
  /// The [pkamSigner] must be set — it signs the `from` challenge and declares
  /// the signing/hashing algorithm (defaults to rsa2048/sha256).
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
  set pkamSigner(AtPkamSigner? pkamSigner);

  AtPkamSigner? get pkamSigner;

  OutboundConnection? get connection;

  set secondaryAddressFinder(SecondaryAddressFinder secondaryAddressFinder);

  SecondaryAddressFinder get secondaryAddressFinder;

  /// EnrollmentId has to be set for clients that are enrolled through APKAM.
  set enrollmentId(String? enrollmentId);

  String? get enrollmentId;
}
