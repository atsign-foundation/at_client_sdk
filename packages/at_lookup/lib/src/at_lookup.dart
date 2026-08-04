import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/at_lookup_impl.dart';

abstract interface class AtLookUp {
  /// An [AtLookUp] using the algorithms every atServer verifies today:
  /// RSA-2048/SHA-256 PKAM, SHA-512 CRAM, RSA-2048/SHA-256 data-signature
  /// verification.
  ///
  /// [pkamPrivateKey] is a PKCS#8 DER-encoded RSA private key — `base64Decode`
  /// of the string form an atKeys file carries. Omit it for an instance that can
  /// only [cramAuthenticate], which is where activation starts.
  factory AtLookUp.legacy(
    String atSign,
    String rootDomain,
    int rootPort, {
    Uint8List? pkamPrivateKey,
    SecondaryAddressFinder? secondaryAddressFinder,
    String? enrollmentId,
    SecureSocketConfig? secureSocketConfig,
    Map<String, dynamic>? clientConfig,
  }) =>
      AtLookUp.create(
        atSign,
        rootDomain,
        rootPort,
        signingAlgo: RsaSigningAlgo(),
        pkamPrivateKey: pkamPrivateKey,
        secondaryAddressFinder: secondaryAddressFinder,
        enrollmentId: enrollmentId,
        secureSocketConfig: secureSocketConfig,
        clientConfig: clientConfig,
      );

  /// An [AtLookUp] that PKAM-authenticates with ML-DSA-65 (FIPS 204, pure
  /// Dart), for an atsign enrolled with a post-quantum APKAM key.
  ///
  /// CRAM and data-signature verification stay classical: a post-quantum PKAM
  /// key changes neither the digest the atServer expects nor the keypair public
  /// data is signed with.
  ///
  /// [pkamPrivateKey] is the raw 4032-byte ML-DSA-65 secret key.
  factory AtLookUp.pq(
    String atSign,
    String rootDomain,
    int rootPort, {
    Uint8List? pkamPrivateKey,
    SecondaryAddressFinder? secondaryAddressFinder,
    String? enrollmentId,
    SecureSocketConfig? secureSocketConfig,
    Map<String, dynamic>? clientConfig,
  }) =>
      AtLookUp.create(
        atSign,
        rootDomain,
        rootPort,
        signingAlgo: MlDsa65PureDartAlgo(),
        pkamPrivateKey: pkamPrivateKey,
        secondaryAddressFinder: secondaryAddressFinder,
        enrollmentId: enrollmentId,
        secureSocketConfig: secureSocketConfig,
        clientConfig: clientConfig,
      );

  /// An [AtLookUp] with every algorithm named explicitly. Prefer
  /// [AtLookUp.legacy] or [AtLookUp.pq].
  ///
  /// at_lookup owns the wire protocol and makes no algorithm choice of its own.
  /// The algorithms are stateless — key material is passed to them per call —
  /// and the only key retained here is [pkamPrivateKey], because at_lookup
  /// re-authenticates a replaced connection itself, which means signing a fresh
  /// challenge without being asked again.
  ///
  /// [signingAlgo] signs the atServer's `from` challenge and declares the
  /// `signingAlgo`/`hashingAlgo` the `pkam` verb is stamped with, so the verb
  /// cannot claim one algorithm while another produced the signature. It and
  /// [pkamPrivateKey] go together: supply both, or neither for a CRAM-only
  /// instance.
  ///
  /// [hashingAlgo] digests the CRAM secret and challenge, defaulting to
  /// [SHA512HashingAlgo]. [dataAlgo] verifies data signatures for
  /// `lookup(verifyData: true)`, defaulting to [RsaSigningAlgo]; it is separate
  /// from [signingAlgo] because it checks a public key the atServer serves,
  /// belonging to a different keypair.
  factory AtLookUp.create(
    String atSign,
    String rootDomain,
    int rootPort, {
    AtSignatureAlgorithm? signingAlgo,
    Uint8List? pkamPrivateKey,
    AtHashingAlgorithm<List<int>, String>? hashingAlgo,
    AtSignatureAlgorithm? dataAlgo,
    SecondaryAddressFinder? secondaryAddressFinder,
    String? enrollmentId,
    SecureSocketConfig? secureSocketConfig,
    Map<String, dynamic>? clientConfig,
  }) = AtLookupImpl;

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

  /// Performs a PKAM authentication, signing the atServer's `from` challenge
  /// with the signing algorithm and private key this instance was constructed
  /// with.
  ///
  /// Pass [enrollmentId] for a client enrolled through APKAM; it defaults to the
  /// [enrollmentId] this instance was constructed with.
  ///
  /// Throws [UnAuthenticatedException] before contacting the atServer if no
  /// PKAM key was supplied.
  Future<bool> pkamAuthenticate({String? enrollmentId});

  /// Generates digest using from verb response and [secret] and performs a
  /// CRAM authentication to secondary server
  Future<bool> cramAuthenticate(String secret);

  /// Terminates the underlying connection to the atServer
  /// used by this instance of AtLookup
  Future<void> close();

  OutboundConnection? get connection;

  /// Whether this instance currently holds a usable connection. False before the
  /// first verb, and after the atServer or an idle timeout drops the socket.
  bool isConnectionAvailable();

  SecondaryAddressFinder get secondaryAddressFinder;

  /// EnrollmentId for clients enrolled through APKAM, as supplied at
  /// construction. The default [enrollmentId] for [pkamAuthenticate].
  String? get enrollmentId;
}
