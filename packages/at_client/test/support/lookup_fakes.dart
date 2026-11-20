import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart' show AtConstants;
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

  /// Sends what [builder] builds, authenticated or not as `AtLookupImpl`
  /// decides from the builder: a lookup or a scan as its own `auth` says, an
  /// enroll request unauthenticated, any other verb it handles authenticated.
  /// A builder it does not handle sends nothing and fails, as `AtLookupImpl`
  /// reports it timed out. The reply is handled as `AtLookupImpl` handles
  /// it: an empty one throws `AT0014` and an `error:` one throws the
  /// [AtLookUpException] it names; any other is returned.
  @override
  Future<String> executeVerb(VerbBuilder builder) async {
    final bool auth = switch (builder) {
      LookupVerbBuilder(:final auth) || ScanVerbBuilder(:final auth) => auth,
      EnrollVerbBuilder(operation: EnrollOperationEnum.request) => false,
      UpdateVerbBuilder() ||
      DeleteVerbBuilder() ||
      LLookupVerbBuilder() ||
      PLookupVerbBuilder() ||
      StatsVerbBuilder() ||
      ConfigVerbBuilder() ||
      NotifyVerbBuilder() ||
      NotifyStatusVerbBuilder() ||
      NotifyListVerbBuilder() ||
      NotifyAllVerbBuilder() ||
      SyncVerbBuilder() ||
      NotifyRemoveVerbBuilder() ||
      NotifyFetchVerbBuilder() ||
      EnrollVerbBuilder() =>
        true,
      _ => throw AtLookUpException('AT0014', 'Request timed out'),
    };
    final command = builder is UpdateVerbBuilder &&
            builder.operation == AtConstants.updateMeta
        ? builder.buildCommandForMeta()
        : builder.buildCommand();
    final reply = await executeCommand(command, auth: auth);
    if (reply == null || reply.isEmpty) {
      throw AtLookUpException('AT0014', 'Request timed out');
    }
    if (reply.startsWith('error:')) throw errorResponseException(reply);
    return reply;
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
