import 'dart:isolate';

import 'client_probe.dart';

/// An app run from acme_chat.dart that names neither itself nor its version.
Future<void> main(List<String> args, SendPort results) =>
    openUnnamedClientAndReport(results);
