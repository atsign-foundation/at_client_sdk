/// A command-line program needs no SDK import beyond at_client_cli's barrel.
///
/// This file imports `package:at_client_cli/at_client_cli.dart` and nothing
/// else from the SDK. That constraint is the test: if a name a program is
/// told to use stops being re-exported, this file stops compiling.
library;

import 'package:at_client_cli/at_client_cli.dart';
import 'package:test/test.dart';

void main() {
  group('Given a program that imports only at_client_cli', () {
    test(
        'when it opens a client by hand, then the keys, store, transport and '
        'atDirectory are all nameable', () {
      final preference = AtClientPreference()..namespace = 'my_app';
      final FileAtKeysIo keys = CliKeys.fileFor('@alice');
      final store = CliKeys.storageFor('@alice', program: 'my_app');
      final AtLookUpFactory lookUps = secureSocketLookUps();
      final SecondaryAddressFinder atDirectory =
          CacheableSecondaryAddressFinder(
              preference.rootDomain, preference.rootPort);

      expect(Atsign('@alice'), isNotNull);
      expect(keys, isA<WrittenAtKeysIo>());
      expect(store, isA<HiveAtClientStorage>());
      expect(lookUps, isNotNull);
      expect(proxyLookUps(), isNotNull);
      expect(atDirectory, isNotNull);
    });

    test('when it sets up logging, then the io handlers are nameable', () {
      expect(StdErrLoggingHandler(), isNotNull);
      expect(CLILoggingHandler, isA<Type>());
      expect(FileLoggingHandler, isA<Type>());
    });

    test('when it registers an atSign, then the registrar is nameable', () {
      final Registrar registrar =
          RegistrarService(registrarUrl: 'my.atsign.com', apiKey: 'an-api-key');

      expect(registrar.registrarUrl, 'my.atsign.com');
      expect(RegisterOperation.register.wireValue, 'register');
      expect(RegistrarApiEndpoint.registerAtsign.method, HttpMethod.post);
      expect(RegisterAtSignResult, isA<Type>());
    });

    test('when it embeds the tools, then their entry points are nameable', () {
      expect(AtActivate.main, isA<Function>());
      expect(AtRegister.main, isA<Function>());
      expect(CLIBase.fromCommandLineArgs, isA<Function>());
    });
  });
}
