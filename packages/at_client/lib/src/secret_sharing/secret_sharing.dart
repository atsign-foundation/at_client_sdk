/// Same-atSign pairwise secret sharing.
///
/// Multiple atClients frequently authenticate as the same atSign — on
/// different APKAM enrollments, or as several clients of one enrollment.
/// This library lets them share secrets pairwise such that only the target
/// *client* can read them: each client registers a [ClientKeyPackage] (per
/// [PairwiseClientRegistration]), and secrets travel in signed, encrypted
/// [SecretEnvelope]s scoped by application namespace (per
/// [PairwiseSecretSharing]).
///
/// [AtClientSecretSharing] is the ready-made entry point; the mixins are
/// exported for apps that prefer composing them into their own classes.
///
/// **Experimental.** This pairwise API is the substrate for the group-based
/// encryption direction described in `docs/crypto-roadmap.md`: client key
/// packages become MLS-style KeyPackages, and the durable app-facing surface
/// will be `SecureGroup` (per-namespace groups with rotating epoch keys).
/// Expect this surface to be reshaped as that lands; the wire formats are
/// crypto-agile and already post-quantum (X-Wing + AES-256-GCM).
library;

export 'package:at_client/src/secret_sharing/algo_ids.dart';
export 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart';
export 'package:at_client/src/secret_sharing/client_key_package.dart';
export 'package:at_client/src/secret_sharing/pairwise_client_registration.dart';
export 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
export 'package:at_client/src/secret_sharing/secret_envelope.dart';
export 'package:at_client/src/secret_sharing/secret_store.dart';
