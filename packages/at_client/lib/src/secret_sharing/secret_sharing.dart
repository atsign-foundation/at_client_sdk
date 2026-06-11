/// Same-atSign pairwise secret sharing.
///
/// Multiple atClients frequently authenticate as the same atSign — on
/// different APKAM enrollments, or as several clients of one enrollment.
/// This library lets them share secrets pairwise such that only the target
/// *client* can read them: each client registers a [ClientKeyBundle] (per
/// [PairwiseClientRegistration]), and secrets travel in signed, encrypted
/// [SecretEnvelope]s scoped by application namespace (per
/// [PairwiseSecretSharing]).
///
/// [AtClientSecretSharing] is the ready-made entry point; the mixins are
/// exported for apps that prefer composing them into their own classes.
library;

export 'package:at_client/src/secret_sharing/algo_ids.dart';
export 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart';
export 'package:at_client/src/secret_sharing/client_key_bundle.dart';
export 'package:at_client/src/secret_sharing/pairwise_client_registration.dart';
export 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
export 'package:at_client/src/secret_sharing/secret_envelope.dart';
export 'package:at_client/src/secret_sharing/secret_store.dart';
