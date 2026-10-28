/// The Atsign Protocol for a Dart command-line program, daemon or server:
/// [CLIBase], which turns the standard flags into an open client, and the
/// at_activate and at_register tools as [AtActivate] and [AtRegister].
library;

export 'src/cli_base.dart';
export 'src/commands/at_activate.dart';
export 'src/commands/auth_cli_args.dart';
export 'src/keys/cli_keys.dart';
export 'src/register/at_register.dart';
export 'src/register/register.dart';
export 'src/util/proxy_lookups.dart';
export 'src/util/request_enrollment_otp.dart';
export 'src/util/service_factories.dart';
export 'src/util/utils.dart';
