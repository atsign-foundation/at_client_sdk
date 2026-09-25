import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';

import 'src/cut.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('atkeys',
        abbr: 'k', help: 'Path to .atKeys file', mandatory: true)
    ..addOption('app', abbr: 'a', help: 'App namespace', mandatory: true)
    ..addOption('root-domain',
        help: 'Root domain', defaultsTo: 'root.atsign.org')
    ..addOption('root-port', help: 'Root port', defaultsTo: '64')
    ..addOption('out',
        abbr: 'o', help: 'Optional path to write the envelope bytes')
    ..addFlag('dry-run', abbr: 'n', help: 'Do not publish', negatable: false)
    ..addFlag('help', abbr: 'h', help: 'Show usage', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  }

  if (results['help'] as bool) {
    stdout.writeln(parser.usage);
    exit(0);
  }

  final atKeysPath = results['atkeys'] as String;
  final app = results['app'] as String;
  final rootDomain = results['root-domain'] as String;
  final rootPort = int.parse(results['root-port'] as String);
  final outPath = results['out'] as String?;
  final dryRun = results['dry-run'] as bool;

  try {
    final io = FileAtKeysIo(filePath: (_) => atKeysPath);
    final loadedKeys = await io.read('');

    final atSignStr = loadedKeys.atsign;
    if (atSignStr == null) {
      stderr.writeln('Could not find atSign in the .atKeys file');
      exit(1);
    }

    final cutResult = await cutEnvelope(loadedKeys);

    if (outPath != null) {
      await File(outPath).writeAsBytes(cutResult.envelope);
    }

    stdout.writeln(cutResult.passphrase.passphrase);

    if (!dryRun) {
      final cmd = updateCommand(atSignStr, app, cutResult.envelope);
      final enrollmentId = loadedKeys.enrollmentToAuthenticateAs();
      final auth = authenticatorFor(io, atSignStr, enrollmentId: enrollmentId);

      final root = AtRootDomain(rootDomain, rootPort);
      final lookUps = secureSocketLookUps();

      final atLookup = lookUps(
        atSign: atSignStr,
        rootDomain: root,
        authenticator: auth,
      );

      try {
        await atLookup.executeCommand(cmd, auth: true);
      } finally {
        await atLookup.close();
      }

      // Verify with an UNAUTHENTICATED lookup
      final verifyLookup = lookUps(
        atSign: atSignStr,
        rootDomain: root,
        authenticator: null,
      );

      try {
        final recordKey = atKeysRecordKey(atSignStr, app);
        final response = await verifyLookup
            .executeCommand('lookup:$recordKey\n', auth: false);
        final expectedText = utf8.decode(cutResult.envelope);
        final expectedResponse = 'data:$expectedText';

        if (response?.trim() != expectedResponse) {
          stderr.writeln(
              'Verification failed. Expected: $expectedResponse, got: $response');
          exit(1);
        }
      } finally {
        await verifyLookup.close();
      }
    }
  } catch (e) {
    stderr.writeln(e.toString());
    exit(1);
  }
}
