import 'package:meta/meta.dart';

export 'package:at_client/src/client/at_client_impl.dart';
export 'package:at_client/src/client/at_client_spec.dart';
export 'package:at_client/src/client/at_reachability.dart';
export 'package:at_client/src/client/data_event.dart';
export 'package:at_client/src/client/local_secondary.dart';
export 'package:at_client/src/client/remote_secondary.dart';
export 'package:at_client/src/client/request_options.dart';
export 'package:at_client/src/crypto/crypto.dart';
// CryptoRuntime carries the pre-flight readiness query, which an app needs
// before it lets a user compose something the write cannot send.
export 'package:at_client/src/crypto/crypto_runtime.dart';
export 'package:at_client/src/key_stream/key_stream.dart';
export 'package:at_client/src/listener/connectivity_listener.dart';
export 'package:at_client/src/manager/at_client_manager.dart';
export 'package:at_client/src/preference/at_client_preference.dart';
export 'package:at_client/src/preference/pq_posture.dart';
// The key-exchange mode only: `PqPosture.keyExchangeMode` holds one, and
// a posture on the main barrel whose key-exchange value could only be read or
// compared by importing at_auth directly is a knob most apps would never
// find. Composing an enrollment request from it still goes through
// `package:at_auth`.
export 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
// The signing algorithm only. `AtClientPreference.dataSigningKeyAlgorithms`
// takes a set of these and `AtClientImpl.signingAlgoType` returns one, so a
// caller that only imports at_client is handed a value it cannot name and
// asked for a set it cannot build. Everything else about signing — key pairs,
// signers, hashing — still comes from `package:at_chops`.
export 'package:at_chops/at_chops.dart' show SigningAlgoType;
export 'package:at_client/src/response/at_notification.dart';
export 'package:at_client/src/response/enrollment.dart';
// The exception only: approve() throws it after a server-side approval whose
// conveyance refused the advertised key package, and callers need the type to
// tell "approved but cannot decrypt" from "the approval failed". The seam
// interface itself stays internal.
export 'package:at_client/src/enroll/enrollment_conveyance.dart'
    show EnrollmentConveyanceException;
// The algorithm ids only, not the rest of the (experimental) secret-sharing
// surface: `AtClientPreference.keyEstablishmentAlgorithms` lists them, and a
// preference on the main barrel whose values are only nameable through
// `at_client_mixins.dart` is a knob most apps would never find.
export 'package:at_client/src/secret_sharing/algo_ids.dart';
export 'package:at_client/src/rpc/at_rpc.dart';
export 'package:at_client/src/rpc/at_rpc_types.dart';
export 'package:at_client/src/service/enrollment_service.dart';
export 'package:at_client/src/service/notification_service.dart';
export 'package:at_client/src/service/sync_service.dart';
@experimental
export 'package:at_client/src/telemetry/at_client_telemetry.dart';
export 'package:at_client/src/util/at_client_util.dart';
export 'package:at_client/src/util/encryption_util.dart';
export 'package:at_client/src/util/enroll_list_request_param.dart';
export 'package:at_commons/at_commons.dart';

export 'package:at_client/src/collections/collections.dart';

// The following have been deprecated and will be removed in next major version
@Deprecated("Use AtClient.collection for collection-style operations")
export 'package:at_client/src/at_collection/collections.dart';
@Deprecated("Use AtClient.collection for collection-style operations")
export 'package:at_client/src/at_collection/at_collection_model.dart';
@Deprecated("Use AtClient.collection for collection-style operations")
export 'package:at_client/src/at_collection/at_json_collection_model.dart';
@Deprecated("Use AtClient.collection for collection-style operations")
export 'package:at_client/src/at_collection/at_collection_model_factory.dart';
