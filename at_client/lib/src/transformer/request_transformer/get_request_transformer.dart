import 'package:at_client/src/client/request_params.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

/// Class responsible for transforming the Get Request
/// Transforms [AtKey] to [VerbBuilder]
class GetRequestTransformer implements RequestTransformer<AtKey, VerbBuilder> {
  @override
  VerbBuilder transform(AtKey atKey, {RequestParams? requestParams}) {
    // Set the default metadata if not already set.
    atKey.metadata ??= Metadata();
    // Set sharedBy to currentAtSign if not set.
    atKey.sharedBy ??=
        AtClientManager.getInstance().atClient.getCurrentAtSign();
    atKey.sharedBy = AtUtils.formatAtSign(atKey.sharedBy);
    // Get the verb builder for the given atKey
    VerbBuilder verbBuilder = LookUpBuilderManager.get(
        atKey, AtClientManager.getInstance().atClient.getCurrentAtSign()!,
        getRequestParams: requestParams as GetRequestParams);
    return verbBuilder;
  }
}
