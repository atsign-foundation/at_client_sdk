import 'package:at_client/at_client_io.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;

import 'virtualenv_ports.dart';

/// A preference on the virtualenv's atDirectory, at [posture] when one is
/// named and the SDK default otherwise; [cramSecret] is what an activation
/// under it spends.
AtClientPreference vePreference(
        {String? namespace, PqPosture? posture, String? cramSecret}) =>
    (posture == null
        ? AtClientPreference()
        : AtClientPreference(posture: posture))
      ..rootDomain = 'vip.ve.atsign.zone'
      ..rootPort = virtualenvRootPort
      ..namespace = namespace
      ..cramSecret = cramSecret;

/// Activates [atSign] through at_activate's own activation, with the CRAM
/// secret on [settings]' preference, writing its first keys to the keyfile
/// [settings] names; the client the activation opened is stopped once its
/// startup has settled, and a test opens its own afterwards, the way a
/// program does.
Future<void> activateThroughCli(
        String atSign, auth_cli.EnrollerSettings settings) =>
    auth_cli.activate(atSign, settings);

/// A client of [atSign] on the keyfile and store [settings] name, through
/// `Atsign.open`, made the manager's current client.
///
/// Every client of [atSign] still live in this process is stopped first,
/// since `open` refuses while one is. A first open the atServer refuses
/// throws [AtOpenRefusedException]; otherwise the client comes back online
/// or not, and its `connection` says which.
Future<AtClient> openClient(
    String atSign, auth_cli.EnrollerSettings settings) async {
  for (final live in AtClientImpl.liveClientsFor(atSign)) {
    await live.stop();
  }
  final client = await Atsign(atSign).open(
      keys: settings.keysFor(atSign),
      preference: settings.preference,
      storage: settings.storageFor(atSign),
      lookUps: settings.lookUps,
      secondaryAddressFinder: settings.secondaryAddressFinder);
  AtClientManager.getInstance().use(client);
  return client;
}

/// [openClient], failing the test unless the client comes up online.
Future<AtClient> openOnline(
    String atSign, auth_cli.EnrollerSettings settings) async {
  final client = await openClient(atSign, settings);
  final state = client.connection.current;
  if (!state.isOnline) {
    await client.stop();
    throw StateError('$atSign did not come online from '
        '${settings.atKeysFilePath}: $state');
  }
  return client;
}
