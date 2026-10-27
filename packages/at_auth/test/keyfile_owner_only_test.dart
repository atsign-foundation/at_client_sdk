@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

/// Catalogue: features/at_auth/keyfile_owner_only.feature
void main() {
  const atsign = '@alice🛠';
  final umask = _lookUpUmask();
  final logs = _RecordedLogs();
  late Directory dir;
  late int savedUmask;
  late String keyfile;

  setUpAll(() {
    // NOTE: set before anything in this file calls FileAtKeysIo.
    AtSignLogger.defaultLoggingHandler = logs;
  });

  setUp(() async {
    savedUmask = umask(_octal('022'));
    dir = await Directory.systemTemp.createTemp('keyfile_owner_only_');
    keyfile = '${dir.path}/keys/${atsign}_key.atKeys';
    logs.messages.clear();

    final control = File('${dir.path}/control')..writeAsStringSync('');
    expect(_modeOf(control.path), '0644',
        reason: 'under this umask a file written with no mode set is '
            'readable by others, so a 0600 below is the writer\'s doing');
  });

  tearDown(() async {
    umask(savedUmask);
    await dir.delete(recursive: true);
  });

  FileAtKeysIo io() => FileAtKeysIo(filePath: (_) => keyfile);

  Future<void> writeKeyfile({required String mode}) async {
    await io().write(atsign, legacyAtKeys(atsign: atsign.toAtsign()));
    await _chmod(mode, keyfile);
  }

  group('Keyfiles are written owner-only', () {
    test('A new keyfile is created owner-only', () async {
      await io().write(atsign, legacyAtKeys(atsign: atsign.toAtsign()));

      expect(_modeOf(keyfile), '0600',
          reason: 'a new keyfile is readable and writable by its owner alone');
    });

    test('A keyfile at the default path is created owner-only', () async {
      final home = Directory('${dir.path}/home')..createSync();
      final packageConfig = await Isolate.packageConfig;
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${packageConfig!.toFilePath()}',
        File('test/support/write_keyfile_at_default_path.dart').absolute.path,
        atsign,
      ], environment: {
        'HOME': home.path
      });
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');

      expect(_modeOf('${home.path}/.atsign/keys/${atsign}_key.atKeys'), '0600',
          reason: 'a FileAtKeysIo built with no file path writes its keyfile '
              'readable and writable by its owner alone');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('A rewritten keyfile keeps owner-only permissions', () async {
      await writeKeyfile(mode: '600');

      await io().update(atsign.toAtsign(), (keys) => true);

      expect(_modeOf(keyfile), '0600',
          reason: 'a rewritten keyfile keeps owner-only permissions');
    });

    test('A keyfile flushed in full keeps owner-only permissions', () async {
      await writeKeyfile(mode: '600');

      await io().flush(atsign.toAtsign(), await io().read(atsign));

      expect(_modeOf(keyfile), '0600',
          reason: 'a keyfile flushed in full keeps owner-only permissions');
    });

    test('A keyfile with a wider mode is owner-only once rewritten', () async {
      await writeKeyfile(mode: '644');

      await io().update(atsign.toAtsign(), (keys) => true);

      expect(_modeOf(keyfile), '0600',
          reason: 'a rewrite leaves the keyfile owner-only, whatever mode it '
              'had before');
    });

    test('The rolling backup is owner-only', () async {
      await writeKeyfile(mode: '644');
      final backup = '$keyfile.bak';
      File(backup).writeAsBytesSync(File(keyfile).readAsBytesSync());
      await _chmod('644', backup);

      await io().update(atsign.toAtsign(), (keys) => true);

      expect(_modeOf(backup), '0600',
          reason: 'the .bak holds the previous key material, so it is '
              'readable and writable by its owner alone too');
    });

    test('The pre-upgrade copy is owner-only', () async {
      await writeKeyfile(mode: '644');
      expect(jsonDecode(File(keyfile).readAsStringSync()),
          isNot(contains('version')),
          reason: 'the Given is a keyfile in the flat shape');

      await io().update(atsign.toAtsign(), (keys) {
        keys.addKey(symmetricKey('typed'));
        return true;
      });

      final preUpgrade = '$keyfile${FileAtKeysIo.legacyShapeBackupSuffix}';
      expect(File(preUpgrade).existsSync(), isTrue,
          reason: 'the update made the document typed, so the flat one was '
              'copied aside');
      expect(_modeOf(preUpgrade), '0600',
          reason: 'the .pre-v1 copy holds key material, so it is readable '
              'and writable by its owner alone too');
    });

    test(
        'A temporary file left by an interrupted write is replaced, not reused',
        () async {
      await writeKeyfile(mode: '600');
      final leftover = File('$keyfile.tmp')..writeAsStringSync('stale');
      await _chmod('644', leftover.path);
      final held = leftover.openSync();
      addTearDown(held.closeSync);

      await io().update(atsign.toAtsign(), (keys) => true);

      held.setPositionSync(0);
      expect(utf8.decode(held.readSync(1 << 16)), 'stale',
          reason: 'the new document goes to a newly created file, so a '
              'descriptor opened on the leftover reads only what it held');
      expect(_modeOf(keyfile), '0600',
          reason: 'the keyfile is owner-only, not the leftover\'s mode');
    });

    test(
        'A symbolic link left at the temporary file\'s path is replaced, not '
        'followed', () async {
      await writeKeyfile(mode: '600');
      final elsewhere = '${dir.path}/elsewhere';
      Link('$keyfile.tmp').createSync(elsewhere);

      await io().update(atsign.toAtsign(), (keys) => true);

      expect(File(elsewhere).existsSync(), isFalse,
          reason: 'nothing is written where a link left at the temporary '
              'path points');
      expect(FileSystemEntity.typeSync(keyfile, followLinks: false),
          FileSystemEntityType.file,
          reason: 'the keyfile is a file this write created, not the link');
      expect(_modeOf(keyfile), '0600',
          reason: 'the keyfile is readable and writable by its owner alone');
    });

    test('A keyfile rewritten by root keeps its owner and group', () async {
      await writeKeyfile(mode: '600');
      await _chown('1234:2345', keyfile);

      await io().update(atsign.toAtsign(), (keys) => true);

      expect(await _ownerOf(keyfile), '1234:2345',
          reason: 'a keyfile root rewrites keeps the owner and group it had');
      expect(_modeOf(keyfile), '0600',
          reason: 'the keyfile is readable and writable by its owner alone');
    },
        skip: _runningAsRoot
            ? false
            : 'runs only as root, the one account that can give a file to '
                'another owner');

    test(
        "Copies root writes for the first time take the keyfile's owner and "
        'group', () async {
      await writeKeyfile(mode: '600');
      await _chown('1234:2345', keyfile);
      final copies = [
        '$keyfile.bak',
        '$keyfile${FileAtKeysIo.legacyShapeBackupSuffix}'
      ];
      expect(copies.where((copy) => File(copy).existsSync()), isEmpty,
          reason: 'the Given is a flat keyfile with no copies beside it');

      await io().update(atsign.toAtsign(), (keys) {
        keys.addKey(symmetricKey('typed'));
        return true;
      });

      for (final copy in copies) {
        expect(await _ownerOf(copy), '1234:2345',
            reason: 'a copy root writes for the first time takes the '
                'keyfile\'s owner and group: $copy');
        expect(_modeOf(copy), '0600',
            reason: 'the copy is readable and writable by its owner alone: '
                '$copy');
      }
    },
        skip: _runningAsRoot
            ? false
            : 'runs only as root, the one account that can give a file to '
                'another owner');

    test(
        "A backup owned by another account takes the keyfile's owner and "
        'group when root rewrites it', () async {
      await writeKeyfile(mode: '600');
      await _chown('1234:2345', keyfile);
      final backup = '$keyfile.bak';
      File(backup).writeAsStringSync('older');
      await _chown('5678:5678', backup);

      await io().update(atsign.toAtsign(), (keys) => true);

      expect(await _ownerOf(backup), '1234:2345',
          reason: "the .bak takes the keyfile's owner and group, not those of "
              'the file it replaces');
      expect(_modeOf(backup), '0600',
          reason: 'the .bak is readable and writable by its owner alone');
    }, skip: _rootOnly);

    test('Root does not rewrite a keyfile that is a symbolic link', () async {
      final target = '${dir.path}/elsewhere.atKeys';
      await FileAtKeysIo(filePath: (_) => target)
          .write(atsign, legacyAtKeys(atsign: atsign.toAtsign()));
      await _chown('5678:5678', target);
      final before = File(target).readAsBytesSync();
      Directory('${dir.path}/keys').createSync();
      Link(keyfile).createSync(target);

      await expectLater(io().update(atsign.toAtsign(), (keys) => true),
          throwsA(isA<FileSystemException>()),
          reason: 'root does not rewrite a keyfile that is a symbolic link');

      expect(File(target).readAsBytesSync(), before,
          reason: 'the file the link points to is unchanged');
      expect(await _ownerOf(target), '5678:5678',
          reason: 'the file the link points to keeps its owner');
    }, skip: _rootOnly);

    test(
        'A keyfile replaced while root updates it is written with the owner '
        'it was read with', () async {
      await writeKeyfile(mode: '600');
      await _chown('1234:2345', keyfile);
      final theirs = '${dir.path}/theirs.atKeys';
      File(theirs).writeAsStringSync('{}');
      await _chown('5678:5678', theirs);

      await io().update(atsign.toAtsign(), (keys) {
        File(keyfile).renameSync('${dir.path}/moved.atKeys');
        Link(keyfile).createSync(theirs);
        return true;
      });

      expect(FileSystemEntity.typeSync(keyfile, followLinks: false),
          FileSystemEntityType.file,
          reason: 'the keyfile written is a file');
      expect(await _ownerOf(keyfile), '1234:2345',
          reason: 'the keyfile written takes the owner and group it was read '
              'with');
      expect(File(theirs).readAsStringSync(), '{}',
          reason: "the second account's file is unchanged");
      expect(await _ownerOf(theirs), '5678:5678',
          reason: "the second account's file keeps its owner");
    }, skip: _rootOnly);

    test(
        'A keys directory replaced while root updates a keyfile in it is not '
        'written through', () async {
      await writeKeyfile(mode: '600');
      await _chown('1234:2345', keyfile);
      final keys = '${dir.path}/keys';
      await _chown('1234:2345', keys);
      final moved = '${dir.path}/keys.moved';
      final theirs = Directory('${dir.path}/theirs')..createSync();
      final theirKeyfile = '${theirs.path}/${atsign}_key.atKeys';
      File(theirKeyfile).writeAsBytesSync(File(keyfile).readAsBytesSync());
      await _chown('5678:5678', theirKeyfile);
      final theirBytes = File(theirKeyfile).readAsBytesSync();

      await io().update(atsign.toAtsign(), (stored) {
        Directory(keys).renameSync(moved);
        Link(keys).createSync(theirs.path);
        return true;
      });

      expect(_namesIn(theirs), ['${atsign}_key.atKeys'],
          reason: "nothing is written in the second account's directory");
      expect(File(theirKeyfile).readAsBytesSync(), theirBytes,
          reason: "the second account's keyfile is unchanged");
      expect(await _ownerOf(theirKeyfile), '5678:5678',
          reason: "the second account's keyfile keeps its owner");
      final written = '$moved/${atsign}_key.atKeys';
      expect(FileSystemEntity.typeSync(written, followLinks: false),
          FileSystemEntityType.file,
          reason: 'the keyfile written is a file in the directory it was '
              'read from');
      expect(await _ownerOf(written), '1234:2345',
          reason: "the keyfile written takes the first account's owner and "
              'group');
    }, skip: _rootOnly);

    test('Root does not write a keyfile in a directory that is a symbolic link',
        () async {
      final theirs = Directory('${dir.path}/theirs')..createSync();
      final theirKeyfile = '${theirs.path}/${atsign}_key.atKeys';
      await FileAtKeysIo(filePath: (_) => theirKeyfile)
          .write(atsign, legacyAtKeys(atsign: atsign.toAtsign()));
      await _chown('5678:5678', theirKeyfile);
      final theirBytes = File(theirKeyfile).readAsBytesSync();
      Link('${dir.path}/keys').createSync(theirs.path);

      await expectLater(
          io().flush(
              atsign.toAtsign(), legacyAtKeys(atsign: atsign.toAtsign())),
          throwsA(isA<FileSystemException>()),
          reason: 'root does not write a keyfile in a directory that is a '
              'symbolic link');

      expect(_namesIn(theirs), ['${atsign}_key.atKeys'],
          reason: "the second account's directory is unchanged");
      expect(File(theirKeyfile).readAsBytesSync(), theirBytes,
          reason: "the second account's keyfile is unchanged");
      expect(await _ownerOf(theirKeyfile), '5678:5678',
          reason: "the second account's keyfile keeps its owner");
    }, skip: _rootOnly);

    test(
        'A backup path that is a symbolic link is replaced when root '
        'rewrites the keyfile', () async {
      await writeKeyfile(mode: '600');
      await _chown('1234:2345', keyfile);
      final theirs = '${dir.path}/theirs';
      File(theirs).writeAsStringSync('theirs');
      await _chown('5678:5678', theirs);
      final backup = '$keyfile.bak';
      Link(backup).createSync(theirs);

      await io().update(atsign.toAtsign(), (keys) => true);

      expect(FileSystemEntity.typeSync(backup, followLinks: false),
          FileSystemEntityType.file,
          reason: 'the .bak is a file');
      expect(await _ownerOf(backup), '1234:2345',
          reason: "the .bak takes the keyfile's owner and group");
      expect(File(theirs).readAsStringSync(), 'theirs',
          reason: "the second account's file is unchanged");
      expect(await _ownerOf(theirs), '5678:5678',
          reason: "the second account's file keeps its owner");
    }, skip: _rootOnly);

    test('Narrowing a keyfile to owner-only is logged', () async {
      await writeKeyfile(mode: '644');

      await io().update(atsign.toAtsign(), (keys) => true);
      expect(logs.messages.where((m) => m.startsWith('$keyfile ')).toList(),
          [allOf(contains('0644'), contains('0600'))],
          reason: 'one line names the keyfile, the mode it had and the mode '
              'it has now');

      logs.messages.clear();
      await io().update(atsign.toAtsign(), (keys) => true);
      expect(logs.messages.where((m) => m.startsWith('$keyfile ')).toList(),
          isEmpty,
          reason: 'a keyfile that was already owner-only is not narrowed, so '
              'nothing is logged for it');
    });
  });
}

/// The process umask, which dart:io neither reads nor sets.
int Function(int) _lookUpUmask() {
  final libc = DynamicLibrary.process();
  return Platform.isMacOS
      ? libc.lookupFunction<Uint16 Function(Uint16), int Function(int)>('umask')
      : libc
          .lookupFunction<Uint32 Function(Uint32), int Function(int)>('umask');
}

int _octal(String digits) => int.parse(digits, radix: 8);

String _modeOf(String path) =>
    (FileStat.statSync(path).mode & 0x1ff).toRadixString(8).padLeft(4, '0');

Future<void> _chmod(String mode, String path) async {
  final result = await Process.run('chmod', [mode, path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

List<String> _namesIn(Directory directory) =>
    directory.listSync().map((entity) => entity.uri.pathSegments.last).toList()
      ..sort();

Future<void> _chown(String owner, String path) async {
  final result = await Process.run('chown', [owner, path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

Future<String> _ownerOf(String path) async {
  final result = await Process.run(
      'stat', Platform.isMacOS ? ['-f', '%u:%g', path] : ['-c', '%u:%g', path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
}

final _runningAsRoot =
    (Process.runSync('id', ['-u']).stdout as String).trim() == '0';

final Object _rootOnly = _runningAsRoot
    ? false
    : 'runs only as root, the one account that can give a file to another '
        'owner';

class _RecordedLogs implements LoggingHandler {
  final List<String> messages = [];

  @override
  void call(record) => messages.add(record.message);
}
