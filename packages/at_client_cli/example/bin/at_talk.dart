import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_client_cli/at_client_cli.dart';

/// at_talk.dart
///
/// <br/>
/// The Dart twin of the C `at_talk` example, speaking the same wire format as
/// the browser `talk.html` harness: each line on stdin is notified to the peer
/// as `attalk.ai6bh`, and every `attalk.ai6bh` notification is printed.
///
/// `dart run bin/at_talk.dart -a @bob🛠 -t @alice🛠 -r vip.ve.atsign.zone:64`
Future<void> main(List<String> args) async {
  final ArgParser parser = CLIBase.createArgsParser(
      namespace: _namespace, addLegacyRootDomainArg: false)
    ..addOption('to', abbr: 't', mandatory: true, help: 'The peer atSign');
  try {
    final cli = await CLIBase.fromCommandLineArgs(args, parser: parser);
    final atClient = cli.atClient;
    final me = atClient.getCurrentAtSign()!;
    final String to = parser.parse(args)['to'];
    final peer = to.startsWith('@') ? to : '@$to';

    atClient.notificationService
        .subscribe(regex: '$_name\\.$_namespace@', shouldDecrypt: true)
        .where(shouldShow)
        .listen((n) => stdout.write('\n${n.from}: ${n.value}\n$me -> '));

    stdout.write('$me -> ');
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isNotEmpty) await _send(atClient, peer, line);
      stdout.write('$me -> ');
    }
    exit(0);
  } catch (e, st) {
    print(e);
    if (e is ArgumentError || e is FormatException) {
      print(parser.usage);
    } else {
      print('Stack Trace:\n$st');
    }
    exit(1);
  }
}

const _name = 'attalk', _namespace = 'ai6bh';
const _expiry = Duration(seconds: 5);

Future<void> _send(AtClient atClient, String peer, String text) async {
  final key = AtKey()
    ..key = _name
    ..namespace = _namespace
    ..sharedBy = atClient.getCurrentAtSign()
    ..sharedWith = peer
    ..metadata = (Metadata()..ttl = _expiry.inMilliseconds);
  final result = await atClient.notificationService
      .notify(NotificationParams.forUpdate(key, value: text));
  if (result.notificationStatusEnum != NotificationStatusEnum.delivered) {
    stderr.writeln('send failed: ${result.atClientException}');
  }
}

/// Whether an incoming notification should be printed.
bool shouldShow(AtNotification n) {
  // TODO(human): filter replays and self-echoes. Default shows everything.
  return true;
}
