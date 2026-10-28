import 'package:keyfile_capture/keyfile_capture.dart';

/// Writes this release's keyfile fixtures into the directory named in [args].
Future<void> main(List<String> args) => captureAll(args, passphrase: true);
