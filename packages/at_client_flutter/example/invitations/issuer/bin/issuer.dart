import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

/// A stand-in registrar for the Ephemeral Environment: it hands out the EE's
/// atSigns, each with its CRAM secret, one at a time, never the same one
/// twice.
///
/// `POST /atsigns` issues the next atSign not yet issued, as
/// `{"atSign", "cramKey", "rootDomain"}`, or answers 410 when none is left.
/// `GET /atsigns` reports what has been issued and how many remain. What has
/// been issued survives a restart, in the state file.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'cram-keys',
      mandatory: true,
      help: 'The EE\'s /tmp/CRAM_Keys: one "<name> <secret>" per line',
    )
    ..addOption('state', mandatory: true, help: 'Where issued atSigns are kept')
    ..addOption('root-domain', defaultsTo: 'vip.ve.atsign.zone:35000')
    ..addOption('port', defaultsTo: '35100');
  final parsed = parser.parse(args);

  final issuer = Issuer(
    cramKeys: Issuer.parseCramKeys(
      File(parsed['cram-keys']).readAsStringSync(),
    ),
    state: File(parsed['state']),
    rootDomain: parsed['root-domain'],
  );

  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    int.parse(parsed['port']),
  );
  stdout.writeln(
    'issuer listening on http://localhost:${server.port} with '
    '${issuer.remaining} of ${issuer.total} atSigns to issue',
  );
  await for (final request in server) {
    await _handle(issuer, request);
  }
}

Future<void> _handle(Issuer issuer, HttpRequest request) async {
  final response = request.response..headers.contentType = ContentType.json;
  try {
    switch ((request.method, request.uri.path)) {
      case ('POST', '/atsigns'):
        final issued = issuer.issueNext();
        if (issued == null) {
          response.statusCode = HttpStatus.gone;
          response.write(jsonEncode({'error': 'every atSign has been issued'}));
        } else {
          stdout.writeln('issued ${issued['atSign']}');
          response.write(jsonEncode(issued));
        }
      case ('GET', '/atsigns'):
        response.write(
          jsonEncode({'issued': issuer.issued, 'remaining': issuer.remaining}),
        );
      default:
        response.statusCode = HttpStatus.notFound;
        response.write(jsonEncode({'error': 'no such endpoint'}));
    }
  } catch (e) {
    response.statusCode = HttpStatus.internalServerError;
    response.write(jsonEncode({'error': '$e'}));
  }
  await response.close();
}

/// Which of the EE's atSigns have been issued, kept in a state file.
class Issuer {
  final Map<String, String> cramKeys;
  final File state;
  final String rootDomain;
  final List<String> issued;

  Issuer({
    required this.cramKeys,
    required this.state,
    required this.rootDomain,
  }) : issued = state.existsSync()
           ? List<String>.from(jsonDecode(state.readAsStringSync()))
           : [];

  int get total => cramKeys.length;

  int get remaining => cramKeys.keys.where((a) => !issued.contains(a)).length;

  /// Parses `/tmp/CRAM_Keys`, in the EE's order.
  static Map<String, String> parseCramKeys(String text) => {
    for (final line in const LineSplitter().convert(text))
      if (line.trim().split(RegExp(r'\s+')) case [final name, final secret])
        '@$name': secret,
  };

  /// Issues the next atSign not yet issued, or null when none is left.
  ///
  /// The state file is written before the atSign is handed out, so a restart
  /// never issues it again.
  Map<String, String>? issueNext() {
    final next = cramKeys.keys.where((a) => !issued.contains(a)).firstOrNull;
    if (next == null) return null;
    issued.add(next);
    final temp = File('${state.path}.tmp')
      ..writeAsStringSync(jsonEncode(issued));
    temp.renameSync(state.path);
    return {
      'atSign': next,
      'cramKey': cramKeys[next]!,
      'rootDomain': rootDomain,
    };
  }
}
