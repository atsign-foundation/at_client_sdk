import 'dart:io';

import 'package:args/args.dart';

extension PrintAllArgParserUsage on ArgParser {
  static final String singleIndentation = '    ';

  printAllCommandsUsage({
    String? header,
    IOSink? sink,
    int indent = 0,
    bool showParams = true,
    bool showSubCommandParams = false,
  }) {
    sink ??= stderr;

    // header message
    if (header != null) {
      _writelnWithIndentation(sink, indent, header);
    }

    if (showParams) {
      // this parser usage
      List<String> usageLines = usage.split('\n');
      for (final l in usageLines) {
        _writelnWithIndentation(sink, indent + 1, l);
      }
    }

    if (commands.isNotEmpty) {
      _writelnWithIndentation(
          sink, indent, 'Commands: (use "<command> -h" for help)');
      // sub-parsers usage
      for (final n in commands.keys) {
        commands[n]!.printAllCommandsUsage(
          header: n,
          sink: sink,
          indent: (indent + 1),
          showParams: showSubCommandParams,
          showSubCommandParams: showSubCommandParams,
        );
      }
    }
  }

  _writelnWithIndentation(IOSink sink, int indent, String s) {
    for (int i = 0; i < indent; i++) {
      sink.write(singleIndentation);
    }
    sink.writeln(s);
  }
}
