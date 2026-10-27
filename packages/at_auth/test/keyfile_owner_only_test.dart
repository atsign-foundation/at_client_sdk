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

class _RecordedLogs implements LoggingHandler {
  final List<String> messages = [];

  @override
  void call(record) => messages.add(record.message);
}
