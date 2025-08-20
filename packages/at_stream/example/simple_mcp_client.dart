import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_stream/at_stream.dart';
import 'package:at_utils/at_utils.dart';
import 'package:dart_mcp/client.dart';

import 'constants.dart';
import 'mcp_transformers.dart';

void main(List<String> args) async {
  final AtSignLogger log = AtSignLogger('ZTAI MCP Client');
  final ArgParser parser = CLIBase.createArgsParser(
    namespace: Constants.baseNamespace,
    hide: CLIBase.hideableArgs,
  );
  addMcpClientArgsToParser(parser);
  try {
    var base = await CLIBase.fromCommandLineArgs(
      args,
      parser: parser,
      namespace: Constants.baseNamespace,
    );
    final argResults = parser.parse(args);
    final serverAtSign = argResults["mcp-atsign"]! as String;

    await runZonedGuarded(
      () async {
        log.shout("Starting mcp client");
        final client = MCPClient(
          Implementation(name: "Simple MCP Client", version: "0.1.0"),
        );

        final channel =
            await AtNotificationStreamChannel.connect<String, String>(
          base.atClient,
          otherAtsign: serverAtSign,
          baseNamespace: 'mcp',
          domainNamespace: 'simple',
          sendTransformer: SendTransformer(),
          recvTransformer: RecvTransformer(),
        );
        final server = client.connectServer(channel);
        log.shout("Started mcp client");

        log.shout("Sending initialize request");
        final initRes = await server.initialize(
          InitializeRequest(
            protocolVersion: ProtocolVersion.latestSupported,
            capabilities: ClientCapabilities(),
            clientInfo: client.implementation,
          ),
        );
        log.shout("Got initialize response");
        if (initRes.capabilities.tools == null) {
          log.severe("Error: Server doesn't support tools!");
          await server.shutdown();
          await channel.close();
          exit(1);
        }
        log.shout("Notifying initialized");
        server.notifyInitialized();

        log.shout("Listing tools");
        final toolsRes = await server.listTools();

        log.shout("Tools: ${toolsRes.tools.map((t) => t.name).join(', ')}");

        var arguments = {'operation': 'add', 'a': 5, 'b': 3};
        log.shout("Calling calculator tool with: $arguments");
        var result = await server.callTool(
          CallToolRequest(name: "calculate", arguments: arguments),
        );
        log.shout("5+3 = ${(result.content.first as TextContent).text}");

        arguments = {'operation': 'multiply', 'a': 5, 'b': 3};
        log.shout("Calling calculator tool with: $arguments");
        result = await server.callTool(
          CallToolRequest(name: "calculate", arguments: arguments),
        );
        log.shout("5x3 = ${(result.content.first as TextContent).text}");

        arguments = {'operation': 'divide', 'a': 5, 'b': 0};
        log.shout("Calling calculator tool with: $arguments");
        result = await server.callTool(
          CallToolRequest(name: "calculate", arguments: arguments),
        );
        log.shout("5/0 = ${(result.content.first as TextContent).text}");

        log.shout("Closing server connection");
        await server.shutdown();
        log.shout("Waiting for server connection to close");
        await server.done;
        await channel.close();
        log.shout("Server connection has closed");
        exit(0);
      },
      (e, st) {
        log.severe("Error: $e $st", e, st);
        exit(1);
      },
    );
  } catch (e, st) {
    log.severe("Service setup failed", e, st);
    print("$e\n\nUsage:");
    print(parser.usage);
    exit(1);
  }
}

void addMcpClientArgsToParser(ArgParser parser) {
  parser.addOption("mcp-atsign", help: "The atSign running the mcp server");
}
