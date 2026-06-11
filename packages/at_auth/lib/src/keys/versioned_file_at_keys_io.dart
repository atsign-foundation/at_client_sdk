import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_auth/src/keys/at_keys_passphrase_envelope.dart';
import 'package:at_auth/src/keys/legacy/legacy_file_at_keys_io.dart';
import 'package:at_commons/at_commons.dart';

class VersionedFileAtKeysIo extends WrittenAtKeysIo {
  final String Function(String) filePath;
  final String? passPhrase;

  VersionedFileAtKeysIo({
    String Function(String)? filePath,
    super.codec,
    super.resolver,
    super.legacyAtKeysAdapter,
    AtKeysPassphraseEnvelopeCodec? passphraseEnvelopeCodec,
    this.passPhrase,
  })  : filePath = filePath ??
            ((atSign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atSign)),
        super(
          passphraseEnvelopeCodec: passphraseEnvelopeCodec ??
              AtKeysPassphraseEnvelopeCodec(
                decryptionException: (message) => AtKeysDecryptionException(
                  message,
                ),
              ),
        );

  @override
  Future<AtKeysSet> read(
    String atSign, {
    AtKeysReadOptions? options,
  }) async {
    final readOptions = options ?? AtKeysReadOptions(passPhrase: passPhrase);
    final file = File(filePath(atSign));
    if (!file.existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path ${file.path} is valid');
    }

    final decodedJson = jsonDecode(await file.readAsString());
    if (decodedJson is! Map<String, dynamic>) {
      throw AtKeysParseException(
          'Expected atKeys file to contain a JSON object');
    }

    //check for password protected atKeys, decode if necessary
    final atKeysJson = await passphraseEnvelopeCodec.decode(
      decodedJson,
      passPhrase: readOptions.passPhrase,
    );

    //legacy fixed field AtKeys
    if (_isLegacyFixedFieldJson(atKeysJson)) {
      if (!readOptions.allowLegacy) {
        throw AtKeysValidationException(
            'Legacy fixed-field atKeys files are not allowed by the read options');
      }
      return _readLegacy(file, atSign, readOptions);
    }

    //versioned decoding for open style of AtKeysSet
    final document = codec.decodeDocument(atKeysJson);
    if (document.atsign != atSign) {
      throw AtKeysValidationException(
          'Requested atSign "$atSign" does not match atKeys document atSign "${document.atsign}"');
    }
    return resolver.resolve(document);
  }

  bool _isLegacyFixedFieldJson(Map<String, dynamic> json) {
    return auth_constants.keySchemaList.any(json.containsKey);
  }

  Future<AtKeysSet> _readLegacy(
    File file,
    String atSign,
    AtKeysReadOptions options,
  ) async {
    return await LegacyFileAtKeysIo(
      filePath: (_) => file.path,
      passPhrase: options.passPhrase,
    ).read(atSign);
  }

  @override
  Future<void> write(
    String atSign,
    AtKeysSet keys, {
    AtKeysWriteOptions? options,
  }) async {
    throw UnsupportedError('Versioned atKeys write is not implemented yet');
  }

  @override
  Future<void> update(String atsign, AtKeysSet keys) {
    // TODO: implement update
    throw UnimplementedError();
  }
}
