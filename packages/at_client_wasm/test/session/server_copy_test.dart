import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

const _atSign = '@alice';
const _app = 'wavi';
final _root = AtRootDomain('root.example', 64);
final _envelope = Uint8List.fromList(utf8.encode('{"v":1,"unlocks":[]}'));

class ScriptedAtLookUp implements AtLookupMuxable {
  ScriptedAtLookUp(this.respond);

  final Future<String?> Function(String command) respond;
  final List<({String command, bool auth})> commands = [];
  bool closed = false;

  @override
  AtAuthenticator? authenticator;

  @override
  Future<String?> executeCommand(String atCommand, {bool auth = false}) {
    commands.add((command: atCommand, auth: auth));
    return respond(atCommand);
  }

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingLookUps {
  RecordingLookUps(this.respond);

  final Future<String?> Function(String command) respond;
  final List<ScriptedAtLookUp> opened = [];
  final List<AtRootDomain> roots = [];

  AtLookupMuxable call(
      {required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder,
      Map<String, dynamic> clientConfig = const {}}) {
    roots.add(rootDomain);
    final lookUp = ScriptedAtLookUp(respond)..authenticator = authenticator;
    opened.add(lookUp);
    return lookUp;
  }
}

void main() {
  group('LookupServerCopyReader', () {
    test('fetch sends an unauthenticated lookup of the record key', () async {
      final lookUps =
          RecordingLookUps((_) async => 'data:${utf8.decode(_envelope)}');
      final reader =
          LookupServerCopyReader(lookUps: lookUps.call, rootDomain: _root);

      expect(await reader.fetch(_atSign, _app), _envelope);
      expect(lookUps.roots.single, _root);
      final lookUp = lookUps.opened.single;
      expect(lookUp.authenticator, isNull);
      expect(lookUp.commands.single,
          (command: 'lookup:_atkeys.wavi@alice\n', auth: false));
    });

    test('fetch closes the connection', () async {
      final lookUps = RecordingLookUps((_) async => 'data:{}');
      await LookupServerCopyReader(lookUps: lookUps.call, rootDomain: _root)
          .fetch(_atSign, _app);
      expect(lookUps.opened.single.closed, isTrue);
    });

    test('fetch is null when the key is not found', () async {
      final lookUps = RecordingLookUps(
          (_) async => throw AtLookUpException('AT0015', 'key not found'));
      final reader =
          LookupServerCopyReader(lookUps: lookUps.call, rootDomain: _root);

      expect(await reader.fetch(_atSign, _app), isNull);
      expect(lookUps.opened.single.closed, isTrue);
    });

    test('fetch is null on data:null', () async {
      final lookUps = RecordingLookUps((_) async => 'data:null');
      expect(
          await LookupServerCopyReader(lookUps: lookUps.call, rootDomain: _root)
              .fetch(_atSign, _app),
          isNull);
    });

    test('fetch propagates other errors and still closes', () async {
      final lookUps = RecordingLookUps(
          (_) async => throw AtLookUpException('AT0014', 'timed out'));
      final reader =
          LookupServerCopyReader(lookUps: lookUps.call, rootDomain: _root);

      await expectLater(
          reader.fetch(_atSign, _app), throwsA(isA<AtLookUpException>()));
      expect(lookUps.opened.single.closed, isTrue);
    });
  });

  group('RemoteServerCopy', () {
    late ScriptedAtLookUp remoteLookUp;
    late RemoteSecondary remote;
    late RecordingLookUps readerLookUps;
    late RemoteServerCopy server;

    setUp(() {
      remoteLookUp = ScriptedAtLookUp((_) async => 'data:1');
      remote = RemoteSecondary(_atSign, AtClientPreference(),
          atLookUp: remoteLookUp);
      readerLookUps =
          RecordingLookUps((_) async => 'data:${utf8.decode(_envelope)}');
      server = RemoteServerCopy(
          LookupServerCopyReader(
              lookUps: readerLookUps.call, rootDomain: _root),
          remote);
    });

    test('put sends updateCommand on the authenticated remote', () async {
      await server.put(_atSign, _app, _envelope);

      expect(remoteLookUp.commands.single,
          (command: updateCommand(_atSign, _app, _envelope), auth: true));
      expect(readerLookUps.opened, isEmpty);
    });

    test('a put envelope is what fetch reads back', () async {
      final written = <String, String>{};
      remoteLookUp = ScriptedAtLookUp((command) async {
        final body = command.substring('update:public:'.length).trimRight();
        final space = body.indexOf(' ');
        written[body.substring(0, space)] = body.substring(space + 1);
        return 'data:1';
      });
      readerLookUps = RecordingLookUps((command) async {
        final key = command.substring('lookup:'.length).trimRight();
        return 'data:${written[key]}';
      });
      server = RemoteServerCopy(
          LookupServerCopyReader(
              lookUps: readerLookUps.call, rootDomain: _root),
          RemoteSecondary(_atSign, AtClientPreference(),
              atLookUp: remoteLookUp));

      await server.put(_atSign, _app, _envelope);
      expect(await server.fetch(_atSign, _app), _envelope);
    });

    test('put does not close the client\'s remote', () async {
      await server.put(_atSign, _app, _envelope);
      expect(remoteLookUp.closed, isFalse);
    });
  });
}
