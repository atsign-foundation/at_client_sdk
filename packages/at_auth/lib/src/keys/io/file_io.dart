import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/file_lock.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// File-backed `.atKeys` storage.
class FileAtKeysIo extends WrittenAtKeysIo {
  String Function(String)? filePath;
  String? passPhrase;

  FileAtKeysIo({this.filePath, this.passPhrase}) {
    filePath ??=
        (atsign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atsign);
  }

  @override
  Future<AtKeys> read(String atsign) async {
    final file = File(filePath!(atsign));
    if (!file.existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path ${file.path} is valid');
    }

    final json = await _readAtRestDocument(file);
    final plaintextJson = await _selfDecryptLegacyFields(json);
    return AtKeys.fromJson(plaintextJson);
  }

  @override
  Future write(String atsign, AtKeys atKeys) async {
    final file = File(filePath!(atsign));
    await AtKeysFileLock(file.path).synchronized(() async {
      if (file.existsSync()) {
        throw AtKeysFileOverwriteException(
            'Tried writing ${file.path}, but failed since it already exists');
      }

      await _writeAtRestDocument(file, await _encodeAtRest(atKeys, atsign));
    });
  }

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) async {
    final file = File(filePath!(atsign));
    // The whole read-validate-write under one inter-process lock. The rename
    // inside is already atomic and `validateMapUpdate` already DETECTS a
    // candidate that drops material — but two processes that both read before
    // either writes both pass validation, and the second rename silently
    // discards the first's addition. Several CLI apps sharing one keyfile is
    // the ordinary deployment, not an edge (`at_client_sdk`
    // docs/projects/pq/decisions.md 38.4).
    await AtKeysFileLock(file.path)
        .synchronized(() => _writeValidated(file, atsign, atKeys));
  }

  /// Read, mutate and write inside **one** hold of the lock.
  ///
  /// [flush] alone cannot close the window this closes: a caller that reads
  /// outside the lock and flushes inside it has already taken its snapshot by
  /// the time the lock is acquired, so a sibling that flushed in between is
  /// missing from its candidate and assurance refuses the write. Holding the
  /// lock across the read is what makes the mutation see the state it is
  /// about to replace. The lock is a lock file, so this serialises coroutines
  /// within one process as well as separate processes — which is the case
  /// that bites, since a client fires the namespace-key seeding and the
  /// conveyed-key filing as sibling unawaited tasks.
  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    final file = File(filePath!(atsign));
    await AtKeysFileLock(file.path).synchronized(() async {
      final keys = await read(atsign.toString());
      if (await mutate(keys) == false) return;
      await _writeValidated(file, atsign, keys);
    });
  }

  /// The flush body, without the lock — so [update] can hold the lock across
  /// its own read as well. `AtKeysFileLock` is not reentrant: calling [flush]
  /// from inside [update] would wait on a lock this call already holds.
  Future<void> _writeValidated(File file, Atsign atsign, AtKeys atKeys) async {
    final document = await _encodeAtRest(atKeys, atsign);

    if (!file.existsSync()) {
      await _writeAtRestDocument(file, document);
      return;
    }

    assurance.validateMapUpdate(
      existing: await _readAtRestDocument(file),
      candidate: document,
    );
    // Keep the previous state recoverable as .bak. A copy, not a rename, so
    // the live keyfile exists at every instant of the flush.
    await file.copy('${file.path}.bak');
    await _writeAtRestDocument(file, document);
  }

  Future<Map<String, dynamic>> _encodeAtRest(
      AtKeys atKeys, String atsign) async {
    final normalized = atsign.toAtsign();
    if (atKeys.atsign != null && atKeys.atsign != normalized) {
      throw AtKeysValidationException(
          'AtKeys belongs to ${atKeys.atsign} but is being persisted for $normalized');
    }
    atKeys.atsign ??= normalized;
    return _selfEncryptLegacyFields(atKeys.toJson());
  }

  Future<Map<String, dynamic>> _readAtRestDocument(File file) async {
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (!passphraseCodec.isEnvelope(json)) return json;
    return passphraseCodec.decode(json, passPhrase: passPhrase);
  }

  Future<void> _writeAtRestDocument(
    File file,
    Map<String, dynamic> document,
  ) async {
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    // Write-to-temp then rename: a crash mid-write can never truncate the
    // keyfile — the rename swaps in the fully-written temp file or leaves
    // the original untouched.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(await _encodePassphraseEnvelope(document));
    await temp.rename(file.path);
  }

  Future<String> _encodePassphraseEnvelope(
      Map<String, dynamic> document) async {
    final plaintext = jsonEncode(document);
    if (passPhrase == null || passPhrase!.isEmpty) {
      return plaintext;
    }
    return passphraseCodec.encode(plaintext, passPhrase!);
  }
}

const _selfEncryptedLegacyFields = [
  auth_constants.apkamPublicKey,
  auth_constants.apkamPrivateKey,
  auth_constants.defaultEncryptionPublicKey,
  auth_constants.defaultEncryptionPrivateKey,
];

Future<Map<String, dynamic>> _selfEncryptLegacyFields(
    Map<String, dynamic> document) {
  return _applyToLegacyFields(
      document,
      (atChops, value) async => (await atChops.encryptString(
              value, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
          .result);
}

Future<Map<String, dynamic>> _selfDecryptLegacyFields(
    Map<String, dynamic> document) {
  return _applyToLegacyFields(
      document,
      (atChops, value) async => (await atChops.decryptString(
              value, EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
          .result);
}

Future<Map<String, dynamic>> _applyToLegacyFields(
  Map<String, dynamic> document,
  Future<String> Function(AtChops atChops, String value) transform,
) async {
  final present = _selfEncryptedLegacyFields
      .where((field) => document[field] != null)
      .toList();
  if (present.isEmpty) {
    return document;
  }
  final selfEncryptionKey =
      document[auth_constants.defaultSelfEncryptionKey] as String?;
  if (selfEncryptionKey == null) {
    throw AtException(
        'selfEncryptionKey is required to process the self-encrypted legacy atKeys fields');
  }
  final atChops =
      AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(selfEncryptionKey));
  final result = Map<String, dynamic>.from(document);
  for (final field in present) {
    result[field] = await transform(atChops, document[field] as String);
  }
  return result;
}

// Copied from at_cli_commons to avoid a circular dependency.
String getDefaultAtKeysFilePath(String homeDirectory, String atsign) {
  return '$homeDirectory/.atsign/keys/${atsign}_key.atKeys'
      .replaceAll('/', Platform.pathSeparator);
}

String? getHomeDirectory({bool throwIfNull = false}) {
  String? homeDir;
  switch (Platform.operatingSystem) {
    case 'linux':
    case 'macos':
      homeDir = Platform.environment['HOME'];
      break;

    case 'windows':
      homeDir = Platform.environment['USERPROFILE'];
      break;

    case 'android':
      homeDir = '/storage/sdcard0';
      break;

    case 'ios':
    case 'fuchsia':
    default:
      homeDir = null;
  }
  if (throwIfNull && homeDir == null) {
    throw ('\nUnable to determine your home directory: please set environment variable\n\n');
  }
  return homeDir;
}
