import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

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

    UpdateVerbBuilder updateVerbBuilder = UpdateVerbBuilder();
    updateVerbBuilder.atKey = tuple.one;
    updateVerbBuilder.noCommit = options.noCommit;
    // Append '@' to the atSign if missed.
    AtClientUtil.fixAtSign(updateVerbBuilder.atKey.sharedWith);
    AtClientUtil.fixAtSign(updateVerbBuilder.atKey.sharedBy);
    // Setting updateVerbBuilder.value
    updateVerbBuilder.value = tuple.two;
    final atKey = updateVerbBuilder.atKey;
    final metadata = atKey.metadata;
    // Check if the data needs to be encrypted for non-public keys.
    //
    // A `local:` key is excluded for the same reason it is excluded in
    // [AtClientImpl] before the pipeline starts: it is never synced to the
    // atServer, so there is nothing for a peer to decrypt and nothing an
    // adversary can capture, and the keystore encrypts it at rest already.
    if (!_isPublicKey(metadata) && !atKey.isLocal && options.shouldEncrypt) {
      // Add metadata for the crypto provider used to route future decrypts.
      updateVerbBuilder.atKey.metadata.appMetadata =
          AppMetadata(providerId: _cryptoProviderIdFor(options, atKey));
      await _encryptData(updateVerbBuilder);
    } else {
      // Sign the data for public keys
      if (_isPublicKey(metadata)) {
        _signPublicData(updateVerbBuilder, encryptionPrivateKey);
      }
      // Encode the data if it contains new line characters
      _encodeIfValueContainsNewLine(updateVerbBuilder);
    }

    return updateVerbBuilder;
  }

  Future<void> _encryptData(UpdateVerbBuilder updateVerbBuilder) async {
    // The provider returns the wire ciphertext and mutates the AtKey's
    // appMetadata + isEncrypted in place.
    updateVerbBuilder.value = await CryptoRuntime(_atClient)
        .encryptForPut(updateVerbBuilder.atKey, updateVerbBuilder.value);
  }

  String _cryptoProviderIdFor(PutRequestOptions options, AtKey atKey) =>
      CryptoRuntime.providerIdFor(_atClient, options.cryptoProviderId,
          atKey: atKey);

  void _signPublicData(
      UpdateVerbBuilder updateVerbBuilder, String? encryptionPrivateKey) {
    if (encryptionPrivateKey.isNull) {
      throw AtPrivateKeyNotFoundException('Failed to sign the public data');
    }
    final atSigningInput = AtSigningInput(updateVerbBuilder.value)
      ..signingMode = AtSigningMode.data;
    final signingResult = _atClient.atChops!.sign(atSigningInput);
    updateVerbBuilder.atKey.metadata.dataSignature = signingResult.result;
  }

  void _encodeIfValueContainsNewLine(UpdateVerbBuilder updateVerbBuilder) {
    if (updateVerbBuilder.value.contains('\n')) {
      updateVerbBuilder.value =
          AtEncoderImpl().encodeData(updateVerbBuilder.value, encodingType);
      updateVerbBuilder.atKey.metadata.encoding = encodingType.toShortString();
    }
  }

  bool _isPublicKey(Metadata metadata) => metadata.isPublic;
}
