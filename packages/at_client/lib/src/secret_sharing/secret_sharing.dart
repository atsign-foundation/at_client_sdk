/// Same-atSign per-APKAM secret sharing.
///
/// Multiple atClients frequently authenticate as the same atSign — on
/// different APKAM enrollments, or as several APKAM keypairs of one
/// enrollment. This library lets them share secrets such that only the target
/// **APKAM keypair** can read them: each APKAM keypair holds a [KeyPackage]
/// (per [KeyPackageRegistration]) conveyed into its enrollment record via
/// `enroll:request`, and secrets travel in signed, encrypted [SecretEnvelope]s
/// addressed by `kpid` and scoped by application namespace (per
/// [PairwiseSecretSharing]). Key packages are discovered via the gated
/// `enroll:listns` verb behind [EnrollmentDirectory] — never published.
///
/// [AtClientSecretSharing] is the ready-made entry point; the mixins are
/// exported for apps that prefer composing them into their own classes.
///
/// Key packages are MLS-style KeyPackages, and the wire formats are
/// crypto-agile and post-quantum (X-Wing or ML-KEM-1024, per the negotiated
/// sealing suite).
library;

export 'package:at_client/src/secret_sharing/algo_ids.dart';
export 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart';
export 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    hide readAdvertisedKeyPackage;
export 'package:at_client/src/secret_sharing/enrollment_key_package.dart';
export 'package:at_client/src/secret_sharing/enrollment_symmetric_key.dart';
export 'package:at_client/src/secret_sharing/key_package.dart';
export 'package:at_client/src/secret_sharing/key_package_registration.dart';
export 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
export 'package:at_client/src/secret_sharing/secret_envelope.dart';
export 'package:at_client/src/secret_sharing/secret_store.dart';
