import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/encryption_service/signin_public_data.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';
import 'package:at_chops/at_chops.dart';

/// Class responsible for transforming the put request from [AtKey] to [VerbBuilder]
class PutRequestTransformer
    extends RequestTransformer<Tuple<AtKey, dynamic>, VerbBuilder> {
  late final AtClient _atClient;

  set atClient(AtClient value) {
    _atClient = value;
  }

  /// the default encoding when the value contains a new line character.
  EncodingType encodingType = EncodingType.base64;

  @override
  // ignore: avoid_renaming_method_parameters
  Future<UpdateVerbBuilder> transform(Tuple<AtKey, dynamic> tuple,
      {String? encryptionPrivateKey, RequestOptions? requestOptions}) async {
    // Populate the update verb builder
    UpdateVerbBuilder updateVerbBuilder =
        _populateUpdateVerbBuilder(tuple.one, _atClient.getPreferences()!);
    // Setting value to updateVerbBuilder
    updateVerbBuilder.value = tuple.two;
    //Encrypt the data for non public keys
    if (!tuple.one.metadata!.isPublic!) {
      var encryptionService = AtKeyEncryptionManager(_atClient)
          .get(tuple.one, _atClient.getCurrentAtSign()!);
      try {
        updateVerbBuilder.value =
            await encryptionService.encrypt(tuple.one, updateVerbBuilder.value);
      } on AtException catch (e) {
        e.stack(AtChainedException(Intent.shareData,
            ExceptionScenario.encryptionFailed, 'Failed to encrypt the data'));
        rethrow;
      }
      updateVerbBuilder.sharedKeyEncrypted = tuple.one.metadata!.sharedKeyEnc;
      updateVerbBuilder.pubKeyChecksum = tuple.one.metadata!.pubKeyCS;
    } else {
      if (encryptionPrivateKey.isNull) {
        throw AtPrivateKeyNotFoundException('Failed to sign the public data');
      }
      //# TODO remove else block once atChops once testing is good
      if (_atClient.getPreferences()!.useAtChops) {
        final signingResult = _atClient.atChops!
            .signString(updateVerbBuilder.value, SigningKeyType.signingSha256);
        updateVerbBuilder.dataSignature = signingResult.result;
      } else {
        // ignore: deprecated_member_use_from_same_package
        updateVerbBuilder.dataSignature = await SignInPublicData.signInData(
            updateVerbBuilder.value, encryptionPrivateKey!);
      }
      // Encode the public data if it contains new line characters
      if (updateVerbBuilder.value.contains('\n')) {
        updateVerbBuilder.value =
            AtEncoderImpl().encodeData(updateVerbBuilder.value, encodingType);
        updateVerbBuilder.encoding = encodingType.toShortString();
      }
    }

    return updateVerbBuilder;
  }

  /// Populated [UpdateVerbBuilder] for the given [AtKey]
  UpdateVerbBuilder _populateUpdateVerbBuilder(
      AtKey atKey, AtClientPreference atClientPreference) {
    UpdateVerbBuilder updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = AtClientUtil.getKeyWithNameSpace(atKey, atClientPreference)
      ..sharedWith = AtUtils.formatAtSign(atKey.sharedWith)
      ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
      ..isPublic =
          (atKey.metadata?.isPublic != null) ? atKey.metadata!.isPublic! : false
      ..isEncrypted = (atKey.metadata?.isEncrypted != null)
          ? atKey.metadata?.isEncrypted!
          : false
      ..isBinary =
          (atKey.metadata?.isBinary != null) ? atKey.metadata?.isBinary! : false
      ..isLocal = atKey.isLocal;

    if (atKey.metadata!.ttl != null) {
      updateVerbBuilder.ttl = atKey.metadata!.ttl;
    }
    if (atKey.metadata!.ttb != null) {
      updateVerbBuilder.ttb = atKey.metadata!.ttb;
    }
    if (atKey.metadata!.ttr != null) {
      updateVerbBuilder.ttr = atKey.metadata!.ttr;
    }
    if (atKey.metadata!.ccd != null) {
      updateVerbBuilder.ccd = atKey.metadata!.ccd;
    }
    updateVerbBuilder.dataSignature = atKey.metadata!.dataSignature;
    return updateVerbBuilder;
  }
}
