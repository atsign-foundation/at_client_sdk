import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/atkeys.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';
import 'package:at_commons/at_commons.dart';

class VersionedFileAtKeysIo extends WritableAtKeysIo {
  final String Function(String) filePath;
  final String? passphrase;
  final AtKeysPassphraseEnvelopeCodec passphraseEnvelopeCodec;
  bool legacyWrites;

  VersionedFileAtKeysIo({
    super.codec,
    super.resolver,
    this.passphrase,
    String Function(String)? filepath,
    AtKeysPassphraseEnvelopeCodec? passphraseCodec,
    bool? allowLegacyWrites,
  })  : filePath = filepath ??
            ((atsign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atsign)),
        passphraseEnvelopeCodec =
            passphraseCodec ?? const AtKeysPassphraseEnvelopeCodec(),
        legacyWrites = allowLegacyWrites ?? true;

  @override
  FutureOr<void> append({
    required AtKeysMaterial key,
    required WritableAtKeysSet source,
  }) async {
    final file = File(filePath(source.atsign));
    if (!file.existsSync()) {
      await write(source);
      return;
    }

    source.addKey(key);
  }

  @override
  FutureOr<AtKeysSet> read(Atsign atsign) async {
    final file = File(filePath(atsign));
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
      passPhrase: passphrase,
    );

    //legacy fixed field AtKeys
    if (_isLegacyFixedFieldJson(atKeysJson)) {
      return _readLegacy(
        file,
        atsign,
        passphrase: passphrase,
      );
    }

    //versioned decoding for open style of AtKeysSet
    final document = codec.decodeDocument(atKeysJson);
    if (document.atsign != atsign) {
      throw AtKeysValidationException(
          'Requested atSign "$atsign" does not match atKeys document atSign "${document.atsign}"');
    }
    return resolver.resolve(document);
  }

  @override
  FutureOr<void> remove(Atsign atsign) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  @override
  FutureOr<void> update(AtKeysSet atKeys) {
    // TODO: implement update
    throw UnimplementedError();
  }

  @override
  FutureOr<void> write(AtKeysSet atKeys) async {
    if (legacyWrites) {
      await FileAtKeysIo(
        filePath: filePath,
        passPhrase: passphrase,
      ).write(atKeys.atsign, AtKeys.fromAtKeysSet(atKeys));
    } else {
      String path = filePath(atKeys.atsign);
      if (!Directory(path).parent.existsSync()) {
        await Directory(path).parent.create(recursive: true);
      }
      //don't overwrite the file
      if (File(path).existsSync()) {
        throw AtKeysFileOverwriteException(
            'Tried writing $path, but failed since it already exists');
      }
      await _writeVersionedDocument(File(path), atKeys);
    }
  }

  Future<void> _writeVersionedDocument(File file, AtKeysSet atKeys) async {
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    final document = resolver.resolveToDocument(atKeys);
    final map = codec.encodeDocument(document);
    await file.writeAsString(jsonEncode(map));
  }
}

bool _isLegacyFixedFieldJson(Map<String, dynamic> json) {
  return FileAtKeysIo.keySchemaList.any(json.containsKey);
}

Future<AtKeysSet> _readLegacy(
  File file,
  String atSign, {
  String? passphrase,
}) async {
  return await FileAtKeysIo(
    filePath: (_) => file.path,
    passPhrase: passphrase,
  ).read(atSign);
}
