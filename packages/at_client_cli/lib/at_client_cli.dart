/// The Atsign Protocol for a Dart command-line program, daemon or server:
/// [CLIBase], which turns the standard flags into an open client, [CliKeys],
/// and the at_activate and at_register tools as [AtActivate] and
/// [AtRegister]. It re-exports at_client's native API, its storage backends
/// and mixins, the registrar and the logging handlers, so a program needs no
/// other SDK import.
library;

export 'package:at_auth/at_auth.dart'
    show
        HttpMethod,
        Registrar,
        RegistrarApiEndpoint,
        RegistrarService,
        RegisterAtSignResult,
        RegisterOperation;
export 'package:at_client/at_client_io.dart';
export 'package:at_client/hive.dart';
export 'package:at_client/memory.dart';
export 'package:at_client/sqlite.dart';
export 'package:at_client/at_client_mixins.dart';
export 'package:at_utils/at_utils_io.dart'
    show CLILoggingHandler, FileLoggingHandler, StdErrLoggingHandler;

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
