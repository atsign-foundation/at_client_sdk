import 'dart:io';

import 'package:args/args.dart';

class CustomArgParser {
  ArgParser argParser;
  CustomArgParser(this.argParser);

  ArgResults parse(args) {
    ArgResults argResults = argParser.parse(args);

    if (argResults.wasParsed('help')) {
      stdout.writeln(argParser.usage);
      exit(0);
    }

    if (!argResults.wasParsed('atsign')) {
      stderr.writeln(
          '--atsign (or -a) is required. Run with --help (or -h) for more.');
      stderr.writeln('Could not complete process due to invalid arguments');
      exit(1);
    }

    if (!argResults.wasParsed('atKeysPath')) {
      stderr.writeln(
          '--atKeysPath (or -k) is required. Run with --help (or -h) for more.');
      stderr.writeln('Could not complete process due to invalid arguments');
      exit(1);
    }

    return argResults;
  }
}
