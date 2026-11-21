import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// `at_activate onboard` and `at_activate enroll` below the argument parsing.
/// An activation writes the atSign's first keys to the keyfile named and
/// stops the client it opened; an enrollment files its keys in the keyfile
/// named, waits for approval and hands back a client on them, and a request
/// already in that keyfile is resumed rather than repeated.
///
/// The atServer is a mocked lookup answering by verb.
void main() {
  AtSignLogger.root_level = 'SHOUT';
  late Directory dir;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('auth_cli_lifecycle_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  Future<AtClientPreference> preference() async =>
      AuthCliArgs.preferenceUnder(PqPosture.legacy)
        ..rootDomain = InternetAddress.loopbackIPv4.address
        ..rootPort = await refusedPort()
        ..namespace = 'at_activate';

  EnrollerSettings settingsFor(AtClientPreference pref, String keysPath) =>
      EnrollerSettings(pref,
          atKeysFilePath: keysPath, storagePath: '${dir.path}/storage');

  Future<void> expectOwnerOnly(String path) async {
    if (Platform.isWindows) return;
    expect((await FileStat.stat(path)).mode & 0x1FF, 0x180,
        reason: 'the keyfile is readable by its owner alone');
  }

  group('activate', () {
    const atSign = '@newborn';
    const enrollmentId = 'first-1';
    const cramSecret = 'the-one-time-secret';

    /// An atServer as the registrar leaves it, unless [activated], in which
    /// case an activation has already published an encryption public key.
    /// [onPublicKeyLookup] runs before it answers a public key lookup.
    ({MockAtLookupImpl lookUp, List<String> sent}) atServer(
        {bool activated = false, void Function()? onPublicKeyLookup}) {
      final lookUp = MockAtLookupImpl();
      final sent = <String>[];
      when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
      when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((i) async {
        final command = i.positionalArguments.first as String;
        sent.add(command);
        if (command.startsWith('lookup:publickey')) {
          onPublicKeyLookup?.call();
          return activated
              ? 'data:${demo.encryptionPublicKeyMap['@alice🛠']}'
              : 'data:null';
        }
        if (command.startsWith('enroll:')) {
          return 'data:${jsonEncode({
                'enrollmentId': enrollmentId,
                'status': 'approved'
              })}';
        }
        throw StateError('the mocked atServer has no answer for: $command');
      });
      when(() => lookUp.executeVerb(any())).thenAnswer((i) async {
        final builder = i.positionalArguments.first as VerbBuilder;
        sent.add(builder.buildCommand());
        if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
          return 'data:1';
        }
        throw StateError('the mocked atServer has no answer for: '
            '${builder.buildCommand()}');
      });
      when(() => lookUp.pkamAuthenticate())
          .thenAnswer((_) async => true);
      when(() => lookUp.close()).thenAnswer((_) async {});
      when(lookUp.stop).thenAnswer((_) async {});
      when(() => lookUp.dropConnection()).thenAnswer((_) async {});
      when(() => lookUp.isConnectionAvailable()).thenReturn(false);
      return (lookUp: lookUp, sent: sent);
    }

    test(
        'writes the first keys to the keyfile named, secures it, and stops '
        'the client', () async {
      final server = atServer();
      final keysPath = '${dir.path}/${atSign}_key.atKeys';
      final pref =
          settingsFor((await preference())..cramSecret = cramSecret, keysPath);

      await activate(atSign, pref, atLookUp: server.lookUp);

      final keys = await FileAtKeysIo(filePath: (_) => keysPath).read(atSign);
      expect(keys.enrollmentToAuthenticateAs(), enrollmentId);
      expect(keys.holdsAuthenticationMaterial, isTrue);
      expect(server.sent.where((c) => c.startsWith('enroll:')), hasLength(1));
      expect(
          server.sent.any((c) =>
              c.startsWith('delete:') && c.contains(AtConstants.atCramSecret)),
          isTrue,
          reason: 'the activation completed: the one-time secret is gone');
      expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
          reason: 'a command\'s client ends with the command');
      await expectOwnerOnly(keysPath);
    });

    test(
        'refuses an atSign whose atServer already publishes an encryption '
        'key, before minting anything', () async {
      final server = atServer(activated: true);
      final keysPath = '${dir.path}/${atSign}_key.atKeys';
      final pref =
          settingsFor((await preference())..cramSecret = cramSecret, keysPath);

      await expectLater(
          activate(atSign, pref, atLookUp: server.lookUp),
          throwsA(isA<AtClientException>().having(
              (e) => e.message, 'message', contains('already activated'))));

      expect(server.sent.where((c) => c.startsWith('enroll:')), isEmpty);
      expect(File(keysPath).existsSync(), isFalse);
    });

    test('refuses to overwrite a keyfile that is already there', () async {
      final server = atServer();
      final keysPath = '${dir.path}/${atSign}_key.atKeys';
      File(keysPath).writeAsStringSync('{}');
      final pref =
          settingsFor((await preference())..cramSecret = cramSecret, keysPath);

      await expectLater(activate(atSign, pref, atLookUp: server.lookUp),
          throwsA(isA<AtKeysFileOverwriteException>()));

      expect(server.sent, isEmpty,
          reason: 'refused before the atServer was asked anything');
    });

    group(
        'Given a keyfile that appears at the path after the check that the '
        'path is free', () {
      test(
          'when a program calls onboard, then it throws '
          'AtKeysUnusableException naming the keyfile', () async {
        final keysPath = '${dir.path}/${atSign}_key.atKeys';
        final server = atServer(
            onPublicKeyLookup: () =>
                File(keysPath).writeAsStringSync('{"keys":['));
        final args = AuthCliArgs().createOnboardCommandParser().parse([
          '-a', atSign, //
          '-k', keysPath,
          '-c', cramSecret,
          '-r', '127.0.0.1:${await refusedPort()}',
          '--posture', 'legacy',
        ]);

        await expectLater(
            onboard(args,
                program: 'at_activate',
                programVersion: null,
                atLookUp: server.lookUp),
            throwsA(isA<AtKeysUnusableException>()
                .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
                .having((e) => e.source, 'source', keysPath)));
        expect(server.sent.where((c) => c.startsWith('enroll:')), isEmpty,
            reason: 'nothing is enrolled with keys that cannot be read');
      });
    });

    /// Catalogue: features/at_client_cli/registrar_api_key.feature
    test('at_activate onboard with a CRAM secret needs no registrar API key',
        () async {
      final server = atServer();
      final keysPath = '${dir.path}/${atSign}_key.atKeys';
      final pref =
          settingsFor((await preference())..cramSecret = cramSecret, keysPath);
      var registrarClients = 0;

      await HttpOverrides.runZoned(
          () => activate(atSign, pref, atLookUp: server.lookUp),
          createHttpClient: (_) {
        registrarClients++;
        throw StateError('an activation with a CRAM secret asked over HTTP');
      });

      expect(File(keysPath).existsSync(), isTrue,
          reason: 'with no registrar API key given, it activates as before');
      expect(registrarClients, 0, reason: 'it sends nothing to the registrar');
    });
  });

  group('enrolDevice', () {
    const atSign = '@alice🛠';
    const enrollmentId = 'e-1';
    final selfEncryptionKey = demo.aesKeyMap[atSign]!;

    ({MockAtLookupImpl lookUp, List<String> sent}) atServer(
            {required Future<bool> Function(int attempt) decide,
            required List<String> wrapped}) =>
        approvingAtServer(decide: decide, wrapped: wrapped);

    Future<AtClient> enrol(
            AtClientPreference pref, String keysPath, MockAtLookupImpl lookUp,
            {String app = 'wavi', String device = 'phone'}) =>
        enrolDevice(
            atSign: atSign,
            settings: settingsFor(pref, keysPath),
            app: app,
            device: device,
            otp: 'ABC123',
            namespaces: {'wavi': 'rw'},
            signingAlgo: SigningAlgoType.rsa2048,
            retryInterval: const Duration(milliseconds: 10),
            atLookUp: lookUp);

    test(
        'files the keys, waits for approval, secures the keyfile, and hands '
        'back an online client', () async {
      final server = atServer(decide: (_) async => true, wrapped: []);
      final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';

      final client = await enrol(await preference(), keysPath, server.lookUp);

      expect(client.enrollmentId, enrollmentId);
      expect(client.connection.current.isOnline, isTrue);
      final keys = await FileAtKeysIo(filePath: (_) => keysPath).read(atSign);
      expect(keys.enrollmentToAuthenticateAs(), enrollmentId);
      // ignore: deprecated_member_use
      expect(keys.defaultSelfEncryptionKey?.toString(), selfEncryptionKey,
          reason: 'the secret the approver sealed, opened by the handshake');
      await expectOwnerOnly(keysPath);
      await client.stop();
    });

    test('a request already in the keyfile is resumed, not repeated', () async {
      final wrapped = <String>[];
      final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';
      final pref = await preference();
      // Submitted earlier and never approved: the keyfile holds it pending.
      final first = atServer(
          decide: (_) async => throw AtAuthErrorReplyException(
              'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed',
              errorCode: 'AT0026'),
          wrapped: wrapped);
      await Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: 'phone',
          namespaces: {'wavi': 'rw'},
          keys: FileAtKeysIo(filePath: (_) => keysPath),
          preference: pref,
          atLookUp: first.lookUp,
          lookUps: settingsFor(pref, keysPath).lookUps,
          secondaryAddressFinder:
              settingsFor(pref, keysPath).secondaryAddressFinder);
      expect(
          (await FileAtKeysIo(filePath: (_) => keysPath).read(atSign))
              .pendingEnrollmentIds,
          [enrollmentId]);

      final second = atServer(decide: (_) async => true, wrapped: wrapped);
      final err = _Captured();
      final client = await IOOverrides.runZoned(
          () => enrol(pref, keysPath, second.lookUp),
          stderr: () => err);

      expect(second.sent.where((c) => c.startsWith('enroll:')), isEmpty,
          reason: 'the wait resumed from the keyfile; no second request');
      expect(
          err.text,
          contains('Resuming enrollment $enrollmentId, submitted earlier from '
              'this keyfile'));
      expect(client.enrollmentId, enrollmentId);
      expect(
          (await FileAtKeysIo(filePath: (_) => keysPath).read(atSign))
              .enrollmentToAuthenticateAs(),
          enrollmentId);
      await client.stop();
    });

    for (final (app, device) in const [('wavi', 'phone'), ('buzz', 'tablet')]) {
      test(
          'enroll adopts the request its keyfile holds under another app or '
          'device name', () async {
        final wrapped = <String>[];
        final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';
        final pref = await preference();
        final filing = atServer(
            decide: (_) async => throw AtAuthErrorReplyException(
                'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed',
                errorCode: 'AT0026'),
            wrapped: wrapped);
        await Atsign(atSign).enroll(
            otp: 'ABC123',
            app: 'buzz',
            device: 'phone',
            namespaces: {'buzz': 'rw'},
            keys: FileAtKeysIo(filePath: (_) => keysPath),
            preference: pref,
            atLookUp: filing.lookUp,
            lookUps: settingsFor(pref, keysPath).lookUps,
            secondaryAddressFinder:
                settingsFor(pref, keysPath).secondaryAddressFinder);
        final second = atServer(decide: (_) async => true, wrapped: wrapped);
        final err = _Captured();

        final client = await IOOverrides.runZoned(
            () =>
                enrol(pref, keysPath, second.lookUp, app: app, device: device),
            stderr: () => err);

        expect(second.sent.where((c) => c.startsWith('enroll:')), isEmpty,
            reason: 'run as $app on $device: the wait resumed from the '
                'keyfile; no second request');
        expect(
            err.text,
            contains(
                'Resuming enrollment $enrollmentId, filed as buzz on phone'),
            reason: 'run as $app on $device');
        expect(client.enrollmentId, enrollmentId,
            reason: 'run as $app on $device: the approval of the request it '
                'waited on opens the client');
        await client.stop();
      });
    }

    test(
        "enroll resumes this app's request from another device before "
        "another app's", () async {
      final wrapped = <String>[];
      final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';
      final keyfile = FileAtKeysIo(filePath: (_) => keysPath);
      final pref = await preference();
      final filing = atServer(
          decide: (_) async => throw AtAuthErrorReplyException(
              'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed',
              errorCode: 'AT0026'),
          wrapped: wrapped);
      await Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: 'old-phone',
          namespaces: {'wavi': 'rw'},
          keys: keyfile,
          preference: pref,
          atLookUp: filing.lookUp,
          lookUps: settingsFor(pref, keysPath).lookUps,
          secondaryAddressFinder:
              settingsFor(pref, keysPath).secondaryAddressFinder);
      final json = (await keyfile.read(atSign)).toJson();
      final enrollments = json['enrollments'] as List;
      enrollments.add(jsonDecode(jsonEncode(enrollments.single))
        ..['enrollmentId'] = 'e-buzz'
        ..['appName'] = 'buzz'
        ..['deviceName'] = 'phone');
      File(keysPath).deleteSync();
      await keyfile.write(atSign, AtKeys.fromJson(json));
      final held = await keyfile.read(atSign);
      expect(
          held.pendingEnrollmentIds, unorderedEquals([enrollmentId, 'e-buzz']),
          reason: 'the control: the keyfile holds both requests');
      expect(held.enrollmentInfo('e-buzz')?.appName, 'buzz');
      final second = atServer(decide: (_) async => true, wrapped: wrapped);
      final err = _Captured();

      final client = await IOOverrides.runZoned(
          () => enrol(pref, keysPath, second.lookUp,
              app: 'wavi', device: 'new-phone'),
          stderr: () => err);

      expect(second.sent.where((c) => c.startsWith('enroll:')), isEmpty,
          reason: 'the wait resumed from the keyfile; no second request');
      expect(
          err.text,
          contains(
              'Resuming enrollment $enrollmentId, filed as wavi on old-phone'));
      expect(client.enrollmentId, enrollmentId,
          reason: 'the approval of the request it waited on opens the client');
      await client.stop();
    });

    test(
        'enroll names the app and device of each request a keyfile holds '
        'when several are pending and none is its own', () async {
      final wrapped = <String>[];
      final keysPath = '${dir.path}/${atSign}_buzz_key.atKeys';
      final keyfile = FileAtKeysIo(filePath: (_) => keysPath);
      final pref = await preference();
      final filing = atServer(
          decide: (_) async => throw AtAuthErrorReplyException(
              'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed',
              errorCode: 'AT0026'),
          wrapped: wrapped);
      await Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'buzz',
          device: 'iphone',
          namespaces: {'buzz': 'rw'},
          keys: keyfile,
          preference: pref,
          atLookUp: filing.lookUp,
          lookUps: settingsFor(pref, keysPath).lookUps,
          secondaryAddressFinder:
              settingsFor(pref, keysPath).secondaryAddressFinder);
      // NOTE: older releases refused only a second request for the same app
      // and device, so a keyfile could hold both of these.
      final json = (await keyfile.read(atSign)).toJson();
      final enrollments = json['enrollments'] as List;
      enrollments.add(jsonDecode(jsonEncode(enrollments.single))
        ..['enrollmentId'] = 'e-ipad'
        ..['appName'] = 'buzz'
        ..['deviceName'] = 'ipad');
      File(keysPath).deleteSync();
      await keyfile.write(atSign, AtKeys.fromJson(json));
      expect((await keyfile.read(atSign)).pendingEnrollmentIds,
          unorderedEquals([enrollmentId, 'e-ipad']),
          reason: 'the control: the keyfile holds both requests');
      final second = atServer(decide: (_) async => true, wrapped: wrapped);

      await expectLater(
          enrol(pref, keysPath, second.lookUp, app: 'buzz', device: 'mac'),
          throwsA(isA<AtKeysUnusableException>()
              .having((e) => e.cause, 'cause',
                  AtKeysUnusableCause.pendingEnrollment)
              .having((e) => e.source, 'source', keysPath)
              .having(
                  (e) => e.message,
                  'message',
                  allOf(
                      contains('none filed for app "buzz" on device "mac"'),
                      contains('"$enrollmentId" (app "buzz" on device '
                          '"iphone")'),
                      contains('"e-ipad" (app "buzz" on device "ipad")'),
                      contains('--app'),
                      contains('--device'),
                      isNot(contains('name both the app and the device'))))));
      expect(second.sent.where((c) => c.startsWith('enroll:')), isEmpty,
          reason: 'no request is sent');
    });

    group(
        'Given a keyfile whose pending enrollment records no app and no '
        'device', () {
      test(
          'when at_activate enroll runs, then it resumes that enrollment '
          'saying nothing of names', () async {
        final wrapped = <String>[];
        final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';
        final keyfile = FileAtKeysIo(filePath: (_) => keysPath);
        final pref = await preference();
        final filing = atServer(
            decide: (_) async => throw AtAuthErrorReplyException(
                'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed',
                errorCode: 'AT0026'),
            wrapped: wrapped);
        await Atsign(atSign).enroll(
            otp: 'ABC123',
            app: 'buzz',
            device: 'phone',
            namespaces: {'buzz': 'rw'},
            keys: keyfile,
            preference: pref,
            atLookUp: filing.lookUp,
            lookUps: settingsFor(pref, keysPath).lookUps,
            secondaryAddressFinder:
                settingsFor(pref, keysPath).secondaryAddressFinder);
        final json = (await keyfile.read(atSign)).toJson();
        for (final entry in json['enrollments'] as List) {
          (entry as Map)
            ..remove('appName')
            ..remove('deviceName');
        }
        File(keysPath).deleteSync();
        await keyfile.write(atSign, AtKeys.fromJson(json));
        final info = (await keyfile.read(atSign)).enrollmentInfo(enrollmentId);
        expect((info?.appName, info?.deviceName), (null, null),
            reason: 'the control: the keyfile records neither name');
        final second = atServer(decide: (_) async => true, wrapped: wrapped);
        final err = _Captured();

        final client = await IOOverrides.runZoned(
            () => enrol(pref, keysPath, second.lookUp),
            stderr: () => err);

        expect(second.sent.where((c) => c.startsWith('enroll:')), isEmpty,
            reason: 'the wait resumed from the keyfile; no second request');
        expect(
            err.text,
            allOf(contains('Resuming enrollment $enrollmentId\n'),
                isNot(contains('filed')), isNot(contains('submitted'))));
        expect(client.enrollmentId, enrollmentId);
        await client.stop();
      });
    });

    test(
        'enroll shows a recorded app or device name with its control '
        'characters escaped', () async {
      final wrapped = <String>[];
      final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';
      final keyfile = FileAtKeysIo(filePath: (_) => keysPath);
      final pref = await preference();
      final filing = atServer(
          decide: (_) async => throw AtAuthErrorReplyException(
              'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed',
              errorCode: 'AT0026'),
          wrapped: wrapped);
      await Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: 'phone',
          namespaces: {'wavi': 'rw'},
          keys: keyfile,
          preference: pref,
          atLookUp: filing.lookUp,
          lookUps: settingsFor(pref, keysPath).lookUps,
          secondaryAddressFinder:
              settingsFor(pref, keysPath).secondaryAddressFinder);
      final json = (await keyfile.read(atSign)).toJson();
      final entry = (json['enrollments'] as List).single as Map;
      entry['appName'] = 'wa\u001bvi';
      entry['deviceName'] = 'pho\rne';
      File(keysPath).deleteSync();
      await keyfile.write(atSign, AtKeys.fromJson(json));
      final info = (await keyfile.read(atSign)).enrollmentInfo(enrollmentId);
      expect((info?.appName, info?.deviceName), ('wa\u001bvi', 'pho\rne'),
          reason: 'the control: the keyfile records both names as written');
      final second = atServer(decide: (_) async => true, wrapped: wrapped);
      final out = _Captured();
      final err = _Captured();

      final client = await IOOverrides.runZoned(
          () => enrol(pref, keysPath, second.lookUp,
              app: 'buzz', device: 'tablet'),
          stdout: () => out,
          stderr: () => err);

      expect(
          err.text,
          contains('Resuming enrollment $enrollmentId, filed as wa\\u001bvi '
              'on pho\\u000dne'));
      for (final (name, printed) in [
        ('stdout', out.text),
        ('stderr', err.text)
      ]) {
        expect(
            printed
                .replaceAll('\r\u001b[K', '')
                .replaceAll(RegExp(r'\u001b\[[0-9;]*m'), ''),
            allOf(isNot(contains('\u001b')), isNot(contains('\r'))),
            reason: 'on $name, once the colour codes and the line redraw the '
                'command writes itself are taken out');
      }
      await client.stop();
    });
  });
}

/// Stands in for stderr, keeping what is written to it.
class _Captured implements Stdout {
  final List<String> written = [];

  String get text => written.join();

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');

  @override
  bool get hasTerminal => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
