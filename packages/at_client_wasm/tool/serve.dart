import 'dart:io';

import 'package:args/args.dart';

import 'src/static_server.dart';

/// Builds the dev harness and serves it on localhost: one command in place of
/// `tool/build.sh` plus a separately started http-server.
void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port',
        abbr: 'p', defaultsTo: '8080', help: 'Port to listen on')
    ..addFlag('build',
        defaultsTo: true,
        help: 'Run tool/build.sh first; --no-build serves the existing build/')
    ..addFlag('help', abbr: 'h', help: 'Show usage', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
  if (results['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }
  final port = int.tryParse(results['port'] as String);
  if (port == null) {
    stderr.writeln('--port must be a number');
    exit(64);
  }

  if (results['build'] as bool) {
    final build = await Process.start(
        'bash', [Platform.script.resolve('build.sh').toFilePath()],
        mode: ProcessStartMode.inheritStdio);
    final code = await build.exitCode;
    if (code != 0) exit(code);
  }

  final buildDir = Directory.fromUri(Platform.script.resolve('../build'));
  final StaticServer server;
  try {
    server = await serveStatic(buildDir, port: port);
  } on SocketException catch (e) {
    stderr.writeln(
        'cannot listen on :$port (${e.osError?.message ?? e.message})');
    exit(1);
  }

  final pages = buildDir
      .listSync()
      .map((e) => e.uri.pathSegments.last)
      .where((name) => name.endsWith('.html'))
      .toList()
    ..sort();
  stdout.writeln('serving build/ at http://localhost:${server.port}/');
  for (final page in pages) {
    stdout.writeln('  http://localhost:${server.port}/$page');
  }
  stdout
    ..writeln(
        '  ?direct=1        straight to each atSign\'s own atServer, found through the atDirectory; no proxy')
    ..writeln(
        '  &root=host:port  the atDirectory to ask (default root.atsign.org:64)')
    ..writeln(
        '  &wasm=1          dart2wasm build, on pages that load at_client.mjs');
}
