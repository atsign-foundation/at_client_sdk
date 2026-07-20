import 'package:meta/meta.dart';

export 'package:at_client/src/client/at_client_impl.dart';
export 'package:at_client/src/client/at_client_spec.dart';
export 'package:at_client/src/client/data_event.dart';
export 'package:at_client/src/client/local_secondary.dart';
export 'package:at_client/src/client/remote_secondary.dart';
export 'package:at_client/src/client/request_options.dart';
export 'package:at_client/src/crypto/crypto.dart';
export 'package:at_client/src/key_stream/key_stream.dart';
export 'package:at_client/src/listener/connectivity_listener.dart';
export 'package:at_client/src/manager/at_client_manager.dart';
export 'package:at_client/src/preference/at_client_preference.dart';
export 'package:at_client/src/response/at_notification.dart';
export 'package:at_client/src/response/enrollment.dart';
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
