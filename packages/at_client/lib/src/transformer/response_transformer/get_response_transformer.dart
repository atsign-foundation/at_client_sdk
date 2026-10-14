import 'dart:async';
import 'dart:convert';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/src/converters/decoder/at_decoder.dart';
import 'package:at_client/src/crypto/crypto.dart' show legacyCryptoProviderId;
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('GetResponseTransformer');

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
    final cryptoRuntime = CryptoRuntime(_atClient);
    // NOTE: the wire's isEncrypted is tri-state, and
    // AtClientUtil.prepareMetadata collapses absent to false, so it is read
    // before that collapse.
    final Object? wireIsEncrypted = (decodedResponse['metaData']
        as Map<String, dynamic>?)?[AtConstants.isEncrypted];
    if (_shouldDecrypt(atValue.metadata)) {
      if (_isPlainLocalValue(tuple.one, atValue.value)) {
        if (atValue.metadata!.encoding != null) {
          atValue.value = AtDecoderImpl()
              .decodeData(atValue.value, atValue.metadata!.encoding!);
        }
      } else {
        atValue.value =
            await cryptoRuntime.decryptForGet(tuple.one, atValue.value);
      }
    } else if (wireIsEncrypted == false || wireIsEncrypted == 'false') {
      // NOTE: a client before at_client 3.2.1 sent no flag, or false, with a
      // value it had encrypted, and the atServer stores a missing flag as
      // false.
      if (_hasLegacyCiphertextShape(tuple.one, atValue.value)) {
        atValue.value =
            await _decryptOrKeep(cryptoRuntime, tuple.one, atValue.value);
      } else if (atValue.metadata?.encoding != null) {
        atValue.value = AtDecoderImpl()
            .decodeData(atValue.value, atValue.metadata!.encoding!);
      }
    } else {
      // for old data (isEncrypted absent), try decrypting the value.
      // if decryption fails, set the original value.
      try {
        atValue.value =
            await cryptoRuntime.decryptForGet(tuple.one, atValue.value);
      } on FormatException {
        // trying to decrypt plain data will result in FormatException.
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

  bool _shouldDecrypt(Metadata? metadata) {
    return metadata != null && metadata.isEncrypted;
  }

  /// Whether [value], flagged encrypted, is a `local:` record's plain value.
  ///
  /// A local record is stored as given, so a write through a key read back
  /// from an encrypted record could store a plain value under
  /// `isEncrypted: true`. The SDK never encodes a value it encrypts, so an
  /// encoded value is plain. Legacy ciphertext is AES with PKCS7 padding,
  /// base64 encoded: a value that does not decode to a positive multiple of 16
  /// bytes cannot be one.
  static bool _isPlainLocalValue(AtKey atKey, dynamic value) =>
      atKey.isLocal &&
      value is String &&
      _isLegacyOrUnmarked(atKey) &&
      !_hasLegacyCiphertextShape(atKey, value);

  /// Whether [value] could be legacy ciphertext for [atKey]: a string, not
  /// encoded, under no provider other than legacy, and base64 of a positive
  /// multiple of 16 bytes.
  static bool _hasLegacyCiphertextShape(AtKey atKey, dynamic value) {
    if (value is! String || !_isLegacyOrUnmarked(atKey)) return false;
    if (atKey.metadata.encoding != null) return false;
    try {
      final bytes = base64Decode(value);
      return bytes.isNotEmpty && bytes.length % 16 == 0;
    } on FormatException {
      return false;
    }
  }

  static bool _isLegacyOrUnmarked(AtKey atKey) {
    final providerId = atKey.metadata.appMetadata?.providerId;
    return providerId == null || providerId == legacyCryptoProviderId;
  }

  /// [value] decrypted for [atKey], or [value] unchanged when it does not
  /// decrypt.
  static Future<dynamic> _decryptOrKeep(
      CryptoRuntime cryptoRuntime, AtKey atKey, String value) async {
    try {
      return await cryptoRuntime.decryptForGet(atKey, value);
    } on StoppedException {
      rethrow;
    } on Exception catch (e) {
      final keyUnavailable = e is SelfKeyNotFoundException ||
          e is SharedKeyNotFoundException ||
          e is AtPrivateKeyNotFoundException;
      if (!keyUnavailable &&
          (e is AtDecryptionException || e is FormatException)) {
        _logger.info('$atKey is flagged unencrypted and shaped like legacy '
            'ciphertext but did not decrypt, so it is returned as stored: $e');
      } else {
        _logger.warning('$atKey is flagged unencrypted and shaped like legacy '
            'ciphertext, but no key to decrypt it was available, so it is '
            'returned as stored: $e');
      }
      return value;
    }
  }

  /// Return true if key is a public key or a cached public key
  /// Else returns false
  bool _isKeyPublic(String key) {
    return key.startsWith('public:') || key.startsWith('cached:public:');
  }
}
