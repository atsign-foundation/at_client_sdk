import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/encryption_service/sign_in_public_data.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
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

  static final PutRequestOptions defaultOptions = PutRequestOptions();

  @override
  // ignore: avoid_renaming_method_parameters
  Future<UpdateVerbBuilder> transform(Tuple<AtKey, dynamic> tuple,
      {String? encryptionPrivateKey, RequestOptions? requestOptions}) async {
    PutRequestOptions options = (requestOptions != null
        ? requestOptions as PutRequestOptions
        : defaultOptions);
    AtKey atKey = tuple.one;

    // Populate the update verb builder
    UpdateVerbBuilder updateVerbBuilder =
        _populateUpdateVerbBuilder(atKey, _atClient.getPreferences()!);
    // Setting updateVerbBuilder.value
    updateVerbBuilder.value = tuple.two;

    //Encrypt the data for non public keys
    if (!atKey.metadata!.isPublic!) {
      var encryptionService = AtKeyEncryptionManager(_atClient)
          .get(atKey, _atClient.getCurrentAtSign()!);
      try {
        updateVerbBuilder.value = await encryptionService.encrypt(
            atKey, updateVerbBuilder.value,
            storeSharedKeyEncryptedWithData:
                options.storeSharedKeyEncryptedMetadata);
      } on AtException catch (e) {
        e.stack(AtChainedException(Intent.shareData,
            ExceptionScenario.encryptionFailed, 'Failed to encrypt the data'));
        rethrow;
      }
      updateVerbBuilder.sharedKeyEncrypted = atKey.metadata!.sharedKeyEnc;
      updateVerbBuilder.pubKeyChecksum = atKey.metadata!.pubKeyCS;
      updateVerbBuilder.encKeyName = atKey.metadata!.encKeyName;
      updateVerbBuilder.encAlgo = atKey.metadata!.encAlgo;
      updateVerbBuilder.ivNonce = atKey.metadata!.ivNonce;
      updateVerbBuilder.skeEncKeyName = atKey.metadata!.skeEncKeyName;
      updateVerbBuilder.skeEncAlgo = atKey.metadata!.skeEncAlgo;
    } else {
      if (encryptionPrivateKey.isNull) {
        throw AtPrivateKeyNotFoundException('Failed to sign the public data');
      }
      final atSigningInput = AtSigningInput(updateVerbBuilder.value);
      final signingResult = _atClient.atChops!.sign(atSigningInput);
      updateVerbBuilder.dataSignature = signingResult.result;
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
      ..sharedWith = AtClientUtil.fixAtSign(atKey.sharedWith)
      ..sharedBy = AtClientUtil.fixAtSign(atKey.sharedBy)
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
