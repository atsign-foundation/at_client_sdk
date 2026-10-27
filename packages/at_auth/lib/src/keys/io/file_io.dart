import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/file_lock.dart';
import 'package:at_auth/src/keys/io/owner_only_mode_stub.dart'
    if (dart.library.ffi) 'package:at_auth/src/keys/io/owner_only_mode_ffi.dart';
import 'package:at_auth/src/keys/serialization/base64_field.dart';
import 'package:at_auth/src/keys/serialization/json_text.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('FileAtKeysIo');

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
    _refuseAbsent(file);
    final json = await _readAtRestDocument(file);
    final plaintextJson = await _selfDecryptLegacyFields(json);
    return AtKeys.fromJson(plaintextJson);
  }

  void _refuseAbsent(File file) {
    if (!file.existsSync()) {
      // Typed, so a caller can tell "no keyfile yet" from "a keyfile this
      // process cannot read". Both used to arrive as a bare AtException and
      // the only way to separate them was the message text.
      throw AtKeysSourceAbsentException(
          'provided keys file does not exist. Please check whether the file path ${file.path} is valid');
    }
  }

  @override
  Future write(String atsign, AtKeys atKeys) async {
    final file = File(filePath!(atsign));
    await AtKeysFileLock(file.path).synchronized(() async {
      final site = _openSite(file, createParent: true);
      try {
        if (site.exists(file)) {
          throw AtKeysFileOverwriteException(
              'Tried writing ${file.path}, but failed since it already exists');
        }
        await _writeDocument(site, file, await _encodeAtRest(atKeys, atsign));
      } finally {
        site.close();
      }
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
    // the ordinary deployment, not an edge.
    await AtKeysFileLock(file.path).synchronized(() async {
      final site = _openSite(file, createParent: true);
      try {
        await _writeValidated(site, file, atsign, atKeys);
      } finally {
        site.close();
      }
    });
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
      _refuseAbsent(file);
      final site = _openSite(file);
      try {
        final asRead = await site.read(file);
        final json =
            await _decodeAtRestDocument(utf8.decode(asRead.bytes), file);
        final keys = AtKeys.fromJson(await _selfDecryptLegacyFields(json));
        if (await mutate(keys) == false) return;
        await _writeValidated(site, file, atsign, keys,
            requireExisting: true, asRead: asRead);
      } finally {
        site.close();
      }
    });
  }

  /// The flush body, without the lock — so [update] can hold the lock across
  /// its own read as well. `AtKeysFileLock` is not reentrant: calling [flush]
  /// from inside [update] would wait on a lock this call already holds.
  /// [requireExisting] refuses instead of creating when the keyfile is gone.
  /// [update] passes it and [flush] does not: `flush` means "persist these
  /// keys", and creating the file is its first job, while `update` is a
  /// read-modify-write of material that must already be there — its own
  /// [read] throws when the file is absent at the start, so completing by
  /// writing a file that is absent at the end contradicts the call it began.
  ///
  /// What that silently undid: the keyfile is the credential, and deleting it
  /// is how a device is decommissioned. An update in flight when the owner
  /// deletes it would put it back, and nothing said so.
  ///
  /// [asRead] is the keyfile as [update] read it; without it the keyfile is
  /// read here. Either way the copies and the keyfile written take the owner
  /// that read reports.
  Future<void> _writeValidated(
      _Site site, File file, Atsign atsign, AtKeys atKeys,
      {bool requireExisting = false, KeyfileRead? asRead}) async {
    final document = await _encodeAtRest(atKeys, atsign);

    if (!site.exists(file)) {
      if (requireExisting) {
        throw AtKeysSourceAbsentException(
            'Tried updating ${file.path}, but it was deleted while the update '
            'was in flight; nothing was written');
      }
      await _writeDocument(site, file, document);
      return;
    }

    final previous = asRead ?? await site.read(file);
    final existing =
        await _decodeAtRestDocument(utf8.decode(previous.bytes), file);
    assurance.validateMapUpdate(
      existing: existing,
      candidate: document,
    );
    await _preserveLegacyShape(site, file, existing, document, previous);
    // Keep the previous state recoverable as .bak. A copy, not a rename, so
    // the live keyfile exists at every instant of the flush.
    await site.replace(File('${file.path}.bak'), previous.bytes,
        owner: previous.owner);
    await _writeDocument(site, file, document, owner: previous.owner);
  }

  /// Where this write reads and writes [file] and its copies: as root, its
  /// directory opened once without following a symbolic link; otherwise the
  /// paths themselves. [createParent] creates a missing directory first.
  _Site _openSite(File file, {bool createParent = false}) {
    if (createParent && !file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    if (!ownerOnlyWritesAvailable || !runningAsRoot) return _PathSite();
    try {
      return _DirectorySite(KeyfileDirectory.open(file.parent.path));
    } on FileSystemException catch (e) {
      throw FileSystemException(
          'Not writing the keyfile as root: its directory is a symbolic link '
          'or cannot be opened (${e.message})',
          file.path);
    }
  }

  /// The suffix [_preserveLegacyShape] writes the pre-upgrade document under.
  static const legacyShapeBackupSuffix = '.pre-v1';

  /// Copies the keyfile's [previous] bytes aside, once, at the moment its
  /// shape stops being the flat one every published build can read.
  ///
  /// Keyed on that transition and never overwritten, unlike the rolling `.bak`
  /// beside it, which the next write replaces.
  Future<void> _preserveLegacyShape(
    _Site site,
    File file,
    Map<String, dynamic> existing,
    Map<String, dynamic> candidate,
    KeyfileRead previous,
  ) async {
    if (existing.containsKey('version')) return;
    if (!candidate.containsKey('version')) return;
    final backup = File('${file.path}$legacyShapeBackupSuffix');
    if (site.exists(backup)) return;
    await site.replace(backup, previous.bytes, owner: previous.owner);
    _logger.shout(
        'Upgrading ${file.path} to the typed keyfile format: it now carries '
        'per-enrollment key material, which a build older than this one does '
        'not read. The previous document has been copied to ${backup.path} '
        'and will not be overwritten.');
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

  Future<Map<String, dynamic>> _readAtRestDocument(File file) async =>
      _decodeAtRestDocument(await file.readAsString(), file);

  Future<Map<String, dynamic>> _decodeAtRestDocument(
      String text, File file) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException(notValidJson('the atKeys file ${file.path}', e));
    }
    final json = decoded as Map<String, dynamic>;
    if (!passphraseCodec.isEnvelope(json)) return json;
    return passphraseCodec.decode(json, passPhrase: passPhrase);
  }

  Future<void> _writeDocument(
    _Site site,
    File file,
    Map<String, dynamic> document, {
    OwnerAndGroup? owner,
  }) async {
    await site.replace(
        file, utf8.encode(await _encodePassphraseEnvelope(document)),
        owner: owner);
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

/// Where one write reads and writes a keyfile and its copies.
abstract class _Site {
  bool exists(File file);

  Future<KeyfileRead> read(File file);

  /// Replaces [file] with [bytes] through a temporary file renamed over it,
  /// so a crash mid-write leaves [file] as it was rather than truncated.
  /// Where the platform has file modes, [file] ends up readable and writable
  /// by its owner alone, and given [owner] when one is named.
  Future<void> replace(File file, List<int> bytes, {OwnerAndGroup? owner});

  void close() {}
}

/// The files at their paths, as a process that is not root reads and writes
/// them.
class _PathSite extends _Site {
  @override
  bool exists(File file) => file.existsSync();

  @override
  Future<KeyfileRead> read(File file) async =>
      (bytes: await file.readAsBytes(), owner: null);

  @override
  Future<void> replace(File file, List<int> bytes,
      {OwnerAndGroup? owner}) async {
    final temp = File('${file.path}.tmp');
    await _deleteLeftover(temp.path);
    final previousMode = _platformHasFileModes ? _modeOf(file) : null;
    final ownerOnly = await _writeTemporary(temp, bytes);
    await temp.rename(file.path);
    _logNarrowed(file, ownerOnly, previousMode);
  }

  /// Writes [bytes] to [temp], owner-only where the platform has file modes,
  /// and says whether it is.
  Future<bool> _writeTemporary(File temp, List<int> bytes) async {
    if (ownerOnlyWritesAvailable) {
      // NOTE: the temporary file is created by this write, owner-only before
      // any byte reaches it; anything already at its path fails the write.
      final written = writeNewOwnerOnly(temp.path, bytes);
      if (written.modeSet) return true;
      _warnModeNotTaken(temp);
      return false;
    }
    if (_platformHasFileModes) {
      _logger.warning('Writing ${temp.path} without owner-only permissions: '
          'the libc calls that set the mode are not available');
    }
    await temp.writeAsBytes(bytes);
    return false;
  }
}

/// The keyfile's directory, opened once as root, so that every read and
/// write of the keyfile and its copies lands in the directory the keyfile
/// was read from.
class _DirectorySite extends _Site {
  _DirectorySite(this._directory);

  final KeyfileDirectory _directory;

  String _name(File file) => file.path.split(Platform.pathSeparator).last;

  @override
  bool exists(File file) => _directory.exists(_name(file));

  @override
  Future<KeyfileRead> read(File file) async {
    final KeyfileRead read;
    try {
      read = _directory.read(_name(file));
    } on FileSystemException catch (e) {
      throw FileSystemException(
          'Not rewriting the keyfile as root: it is a symbolic link or cannot '
          'be read (${e.message})',
          file.path);
    }
    if (read.owner == null) {
      _logger.warning('Writing ${file.path} owned by root: the owner of the '
          'keyfile could not be read');
    }
    return read;
  }

  @override
  Future<void> replace(File file, List<int> bytes,
      {OwnerAndGroup? owner}) async {
    final previousMode = _modeOf(file);
    final written = _directory.replace(_name(file), bytes, owner: owner);
    if (!written.ownerSet) {
      _logger.warning('Wrote ${file.path} owned by root: it could not be '
          'given uid ${owner!.uid} and gid ${owner.gid}, which own the '
          'keyfile');
    }
    if (!written.modeSet) _warnModeNotTaken(file);
    _logNarrowed(file, written.modeSet, previousMode);
  }

  @override
  void close() => _directory.close();
}

void _warnModeNotTaken(File file) {
  _logger.warning('Wrote ${file.path} without owner-only permissions: its '
      'file system did not take mode ${_octal(ownerOnlyMode)}');
}

void _logNarrowed(File file, bool ownerOnly, int? previousMode) {
  if (ownerOnly && previousMode != null && previousMode & 0x3f != 0) {
    _logger.info('${file.path} is now readable and writable by its owner '
        'alone: mode ${_octal(ownerOnlyMode)}, was ${_octal(previousMode)}');
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
      (algorithm, _, value) async => base64.encode(await algorithm.encrypt(
          Uint8List.fromList(utf8.encode(value)),
          iv: InitialisationVector.legacy())));
}

Future<Map<String, dynamic>> _selfDecryptLegacyFields(
    Map<String, dynamic> document) {
  return _applyToLegacyFields(
      document,
      (algorithm, field, value) async => utf8.decode(await algorithm.decrypt(
          decodeBase64Field(value, field),
          iv: InitialisationVector.legacy())));
}

/// Applies [transform] to whichever of the self-encrypted legacy fields the
/// document holds, under the key it carries in the clear.
///
/// The all-zero initialisation vector both transforms pass makes this an
/// at-rest format rather than a choice: every `.atKeys` file on disk was
/// written that way, and `legacy_field_self_encryption_test.dart` pins the
/// bytes against openssl.
Future<Map<String, dynamic>> _applyToLegacyFields(
  Map<String, dynamic> document,
  Future<String> Function(
          AESEncryptionAlgo algorithm, String field, String value)
      transform,
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
  // NOTE: a malformed key fails here, by field name, not inside the cipher.
  decodeBase64Field(selfEncryptionKey, auth_constants.defaultSelfEncryptionKey);
  final algorithm = AESEncryptionAlgo(AESKey(selfEncryptionKey));
  final result = Map<String, dynamic>.from(document);
  for (final field in present) {
    result[field] =
        await transform(algorithm, field, document[field] as String);
  }
  return result;
}

/// Removes whatever an interrupted write left at [path], without following
/// a symbolic link there.
Future<void> _deleteLeftover(String path) async {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    await Link(path).delete();
  } else if (type == FileSystemEntityType.file) {
    await File(path).delete();
  }
}

bool get _platformHasFileModes => Platform.isLinux || Platform.isMacOS;

/// The permission bits of [file], or null when it does not exist.
int? _modeOf(File file) {
  final stat = file.statSync();
  if (stat.type == FileSystemEntityType.notFound) return null;
  return stat.mode & 0x1ff;
}

String _octal(int mode) => mode.toRadixString(8).padLeft(4, '0');

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
