import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

/// Class responsible for transforming the Get Request
/// Transforms [AtKey] to [VerbBuilder]
class GetRequestTransformer implements RequestTransformer<AtKey, VerbBuilder> {
  late final AtClient _atClient;

  GetRequestTransformer(this._atClient);

  @override
  VerbBuilder transform(AtKey atKey, {RequestOptions? requestOptions}) {
    // Set the default metadata if not already set.
    atKey.metadata ??= Metadata();
    // Set sharedBy to currentAtSign if not set.
    atKey.sharedBy ??= _atClient.getCurrentAtSign();
    atKey.sharedBy = AtUtils.formatAtSign(atKey.sharedBy);
    // Get the verb builder for the given atKey
    VerbBuilder verbBuilder;
    if (requestOptions != null) {
      verbBuilder = LookUpBuilderManager.get(
          atKey, _atClient.getCurrentAtSign()!, _atClient.getPreferences()!,
          getRequestOptions: requestOptions as GetRequestOptions);
    } else {
      verbBuilder = LookUpBuilderManager.get(
          atKey, _atClient.getCurrentAtSign()!, _atClient.getPreferences()!);
    }
    return verbBuilder;
  }
}
