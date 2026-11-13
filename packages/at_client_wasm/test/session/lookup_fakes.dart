import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';

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
