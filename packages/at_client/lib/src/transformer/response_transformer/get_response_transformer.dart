import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/src/converters/decoder/at_decoder.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_commons/at_commons.dart';

/// Class responsible for transforming the Get response
/// Transform's the Get Response to [AtValue]
///
/// Decodes the binary data and decrypts the encrypted data
class GetResponseTransformer
    implements Transformer<Tuple<AtKey, String>, AtValue> {
  late final AtClient _atClient;

  GetResponseTransformer(this._atClient);

  @override
  FutureOr<AtValue> transform(Tuple<AtKey, String> tuple) async {
    var atValue = AtValue();
    var decodedResponse =
        JsonUtils.decodeJson(DefaultResponseParser().parse(tuple.two).response);

    atValue.value = decodedResponse['data'];
    // parse metadata
    if (decodedResponse['metaData'] != null) {
      final metadata = AtClientUtil.prepareMetadata(
          decodedResponse['metaData'], _isKeyPublic(decodedResponse['key']),
          isCached: decodedResponse['key'].startsWith('cached:'));
      atValue.metadata = metadata;
      tuple.one.metadata = metadata!;
    }
    // For public and cached public keys, data is not encrypted.
    if (_isKeyPublic(decodedResponse['key'])) {
      return _handlePublicData(atValue, tuple);
    }

    var decryptionService = AtKeyDecryptionManager(_atClient)
        .get(tuple.one, _atClient.getCurrentAtSign()!);
    // Decrypt the data, for other keys
    // For new encrypted data after AtClient v3.2.1, isEncrypted will be true by default
    if (_shouldDecrypt(atValue.metadata)) {
      atValue.value = await _decrypt(atValue, decryptionService, tuple.one);
    } else {
      // for old data, try decrypting the value. if decryption fails, set the original value.
      try {
        atValue.value = await _decrypt(atValue, decryptionService, tuple.one);
      } on Exception {
        if (atValue.metadata!.encoding != null) {
          atValue.value = AtDecoderImpl()
              .decodeData(atValue.value, atValue.metadata!.encoding!);
        }
      }
    }
    // After decrypting the data, if data is binary, decode the data
    // For cached keys, isBinary is not on server-side. Hence getting
    // isBinary from AtKey.
    if (tuple.one.metadata.isBinary) {
      atValue.value = Base2e15.decode(atValue.value);
    }
    return atValue;
  }

  AtValue _handlePublicData(AtValue atValue, Tuple<AtKey, String> tuple) {
    if (atValue.metadata?.encoding != null) {
      atValue.value = AtDecoderImpl()
          .decodeData(atValue.value, atValue.metadata!.encoding!);
    }

    if (tuple.one.metadata.isBinary) {
      atValue.value = Base2e15.decode(atValue.value);
    }

    return atValue;
  }

  Future<String> _decrypt(
      AtValue atValue, AtKeyDecryption decryptionService, AtKey atKey) async {
    try {
      return await decryptionService.decrypt(atKey, atValue.value) as String;
    } on AtException catch (e) {
      e.stack(AtChainedException(Intent.fetchData,
          ExceptionScenario.decryptionFailed, 'Failed to decrypt the data'));
      rethrow;
    }
  }

  bool _shouldDecrypt(Metadata? metadata) {
    return metadata != null && metadata.isEncrypted;
  }

  /// Return true if key is a public key or a cached public key
  /// Else returns false
  bool _isKeyPublic(String key) {
    return key.startsWith('public:') || key.startsWith('cached:public:');
  }
}
