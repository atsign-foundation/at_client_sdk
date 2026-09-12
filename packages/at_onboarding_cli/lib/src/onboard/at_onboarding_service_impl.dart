import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/src/factory/service_factories.dart';
import 'package:at_onboarding_cli/src/onboard/at_onboarding_service.dart';
import 'package:at_onboarding_cli/src/util/at_onboarding_preference.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

import '../util/home_directory_util.dart';

/// [AtOnboardingService] over `Atsign.open` and `AtClientManager.use`.
class AtOnboardingServiceImpl implements AtOnboardingService {
  final Atsign _atSign;
  final AtSignLogger logger = AtSignLogger('OnboardingCli');
  AtOnboardingPreference atOnboardingPreference;

  /// Decides the services the client runs on. A factory whose sync service
  /// does nothing is how a CLI opts out of sync, and
  /// `AtOnboardingPreference.skipSync` selects that one.
  AtServiceFactory? atServiceFactory;

  final AtLookUp? _atLookUp;

  @override
  AtClient? atClient;

  /// [enrollmentId] names the enrollment whose local storage the client uses
  /// when the preference names no storage path. [atLookUp] is a connection
  /// to open the client over instead of one built from the preference.
  AtOnboardingServiceImpl(
    String atsign,
    this.atOnboardingPreference, {
    this.atServiceFactory,
    String? enrollmentId,
    @visibleForTesting AtLookUp? atLookUp,
  })  : _atSign = atsign.toAtsign(),
        _atLookUp = atLookUp {
    atOnboardingPreference.storagePath ??=
        // ignore: deprecated_member_use
        atOnboardingPreference.hiveStoragePath ??
            HomeDirectoryUtil.getHiveStoragePath(_atSign,
                enrollmentId: enrollmentId);
    atOnboardingPreference.atKeysFilePath ??=
        HomeDirectoryUtil.getAtKeysPath(_atSign);
  }

  /// The keyfile the preference names, as the store the client opens on.
  FileAtKeysIo get keyfile => FileAtKeysIo(
      filePath: (_) => atOnboardingPreference.atKeysFilePath!,
      passPhrase: atOnboardingPreference.passPhrase);

  @override
  Future<bool> authenticate() async {
    final held = atClient;
    if (held != null) {
      await held.stop();
      atClient = null;
    }
    if (atOnboardingPreference.skipSync) {
      atServiceFactory = ServiceFactoryWithNoOpSyncService();
    }
    final AtClient client;
    try {
      client = await _atSign.open(
          keys: keyfile,
          preference: atOnboardingPreference,
          storage: atOnboardingPreference.storageFor(_atSign),
          serviceFactory: atServiceFactory,
          atLookUp: _atLookUp);
    } on AtOpenRefusedException catch (e) {
      logger.warning(e.message);
      return false;
    }
    AtClientManager.getInstance().use(client);
    atClient = client;
    final state = client.connection.current;
    if (!state.isOnline) {
      logger.warning('$_atSign opened but is ${state.outcome.name}'
          '${state.cause == null ? '' : ' (${state.cause!.name})'}');
    }
    return state.isOnline;
  }

  @override
  @Deprecated('use atClient')
  Future<AtClient?> getAtClient() async => atClient;
}
