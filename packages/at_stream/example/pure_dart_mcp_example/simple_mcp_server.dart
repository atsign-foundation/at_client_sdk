import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_utils/at_utils.dart';
import 'package:dart_mcp/server.dart';
import 'package:at_stream/at_stream.dart';

import 'constants.dart';
import 'mcp_transformers.dart';

void main(List<String> args) async {
  /// Logger
  final AtSignLogger log = AtSignLogger('ZTAI MCP Server');

  /// Setup a base atPlatform CLI app
  final ArgParser parser = CLIBase.createArgsParser(
    namespace: Constants.baseNamespace,
    hide: CLIBase.hideableArgs,
  );

  /// Function below which adds your customizations to the CLI parser
  addMcpServerArgsToParser(parser);

  try {
    /// Create the CLI base
    var base = await CLIBase.fromCommandLineArgs(
      args,
      parser: parser,
      namespace: Constants.baseNamespace,
    );

    /// Parse your customized arguments
    final argResults = parser.parse(args);
    final policy = argResults["policy-manager"] as String?;

    log.shout("Starting service with policy: $policy");
    await runZonedGuarded(
      () async {
        /// See completer in the Dart SDK
        /// this completer tracks when the bind stream closes
        final completer = Completer();

        /// Bind an [AtNotificationStreamChannel]
        /// Bind makes it act like a [ServerSocket]
        AtNotificationStreamChannel.bind<String, String>(
          base.atClient, // Pass in the atClient from CLI base
          baseNamespace: 'mcp',
          domainNamespace: 'simple',

          // Transformer which encodes sent data
          // If you want to do special behavior every time you send a message
          // you can add the special behavior there.
          sendTransformer: SendTransformer(),

          // Transformer which decodes received data
          // If you want to do special behavior every time you receive a message
          // you can add the special behavior there.
          //
          // You can also ignore unauthorized messages by not adding them to the
          // returned stream in [StreamTransformer.bind].
          recvTransformer: RecvTransformer(),
          logger: log, // Optional: pass in a logger to log messages internally
        ).listen((channel) async {
          /// Create your MCP server using the AtNotificationStreamChannel
          /// provided by the bind Stream
          SimpleMcpServer(channel);

          /// This waits for the channel to close (i.e. the MCP server is done)
          /// Then logs a message
          unawaited(
            channel.done
                .then((_) => log.shout("Channel ${channel.sessionId} is done")),
          );
        }, onDone: completer.complete);
        await completer.future;
      },
      (e, st) {
        log.severe("Error starting service: $e", e, st);
        exit(1);
      },
    );
  } catch (e, st) {
    log.severe("Service setup failed", e, st);
    print("$e\n\nUsage:");
    print(parser.usage);
    exit(1);
  }
  log.shout("Server disconnected");
  exit(0);
}

void addMcpServerArgsToParser(ArgParser parser) {
  parser.addOption(
    "policy-manager",
    abbr: "p",
    help: "The atSign to lookup policy from",
  );
}

/// Basic calculator MCP tool implementation using package:dart_mcp
/// See that package's documentation to learn more, this package doesn't
/// do anything special with it.
///
/// The channel parameter is where we choose the transport...
/// instead of using Stdio or HTTP, you can use [AtNotificationStreamChannel]
/// to transport MCP over the AtPlatform.
final class SimpleMcpServer extends MCPServer with ToolsSupport {
  SimpleMcpServer(super.channel)
      : super.fromStreamChannel(
          implementation: Implementation(
            name: "Simple Mcp Server",
            version: "0.1.0",
          ),
        );

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    registerTool(calculatorTool, _calculatorTool);
    return super.initialize(request);
  }
}

final calculatorTool = Tool(
  name: "calculate",
  description: 'Mathematical operation to perform',
  inputSchema: Schema.object(
    properties: {
      'operation': Schema.string(
        enumValues: ['add', 'subtract', 'multiply', 'divide'],
        description: 'Mathematical operation to perform',
      ),
      'a': Schema.num(description: 'First operand'),
      'b': Schema.num(description: 'Second operand'),
    },
    required: ['operation', 'a', 'b'],
  ),
);

Future<CallToolResult> _calculatorTool(CallToolRequest request) async {
  final arguments = request.arguments!;
  final operation = arguments['operation'] as String;
  final a = (arguments['a'] is int)
      ? (arguments['a'] as int).toDouble()
      : arguments['a'] as double;
  final b = (arguments['b'] is int)
      ? (arguments['b'] as int).toDouble()
      : arguments['b'] as double;

  double result;
  switch (operation) {
    case 'add':
      result = a + b;
      break;
    case 'subtract':
      result = a - b;
      break;
    case 'multiply':
      result = a * b;
      break;
    case 'divide':
      if (b == 0) {
        return CallToolResult(
          content: [TextContent(text: 'Division by zero error')],
          isError: true,
        );
      }
      result = a / b;
      break;
    default:
      return CallToolResult(
        content: [TextContent(text: 'Unknown operation: $operation')],
        isError: true,
      );
  }

  return CallToolResult(content: [TextContent(text: 'Result: $result')]);
}
