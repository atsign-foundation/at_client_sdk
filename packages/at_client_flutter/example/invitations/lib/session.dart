import 'dart:io';

import 'package:at_client/at_client_mixins.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'issuer.dart';

/// The namespace the invitations live under.
const String invitationsNamespace = 'my_app';

/// The root domains the sign-in dialogs offer: the public atDirectory, and
/// the Ephemeral Environment the invitations example's scripts run.
final Map<String, AtRootDomain> rootDomains = {
  'root.atsign.org': AtRootDomain.atsignDomain,
  'vip.ve.atsign.zone:35000': AtRootDomain.parse('vip.ve.atsign.zone:35000'),
};

/// The signed-in atSign, and its invitations.
///
/// The app runs only at [PqPosture.pqActive]:
/// everything it shares is sealed post-quantum, and a write that cannot be is
/// refused rather than sent under legacy encryption.
class Session extends ChangeNotifier {
  static final Session instance = Session._();

  Session._();

  final KeychainStorage _keychain = KeychainStorage();

  /// Where keys are kept: the keychain, unless this names a directory to keep
  /// keyfiles in. The integration test sets it, because the macOS keychain
  /// can stop to ask whoever is at the keyboard.
  @visibleForTesting
  static String? keyfileDirectory;

  WrittenAtKeysIo _keys() => keyfileDirectory == null
      ? KeychainAtKeysIo()
      : FileAtKeysIo(filePath: (atSign) => '$keyfileDirectory/$atSign.atKeys');
  final Map<String, AtRootDomain> _rootDomainOf = {};

  AtClientInvitations? _invitations;

  AtClientInvitations? get invitations => _invitations;

  /// The atSigns signed in during this run, which [signInFromKeychain] can
  /// sign in as again without asking for a root domain.
  List<String> get recentAtSigns => _rootDomainOf.keys.toList();

  /// The atSigns this device can sign in as without onboarding again.
  Future<List<String>> knownAtSigns() async => keyfileDirectory == null
      ? await _keychain.getAllAtsigns()
      : recentAtSigns;

  /// Signs in as an atSign held in the keychain. With [atSign], and a root
  /// domain remembered for it, no atSign dialog is shown.
  Future<bool> signInFromKeychain(
    BuildContext context, {
    String? atSign,
  }) async {
    var rootDomain = atSign == null ? null : _rootDomainOf[atSign];
    if (atSign == null || rootDomain == null) {
      final existing = atSign == null ? await knownAtSigns() : [atSign];
      if (!context.mounted) return false;
      final selection = await AtSignSelectionDialog.show(
        context,
        existingAtSigns: existing,
        existingDomains: rootDomains,
      );
      if (selection == null || !context.mounted) return false;
      atSign = selection.atSign;
      rootDomain = selection.rootDomain;
    }
    final storage = await _storage(atSign, rootDomain);
    if (!context.mounted) return false;
    final client = await PkamDialog.show(
      context,
      atSign: atSign,
      rootDomain: rootDomain,
      keys: _keys(),
      preference: _preference(),
      storage: storage,
    );
    return _open(client, rootDomain);
  }

  /// Gets a new atSign from the issuer and activates it, as someone who has
  /// just got an atSign from a registrar does.
  Future<bool> getNewAtSign(BuildContext context) async {
    final issued = await issueAtSign();
    final storage = await _storage(
      issued.atSign,
      issued.rootDomain,
      fresh: true,
    );
    if (!context.mounted) return false;
    final client = await CramDialog.show(
      context,
      atSign: issued.atSign,
      cramKey: issued.cramKey,
      rootDomain: issued.rootDomain,
      keys: _keys(),
      preference: _preference(),
      storage: storage,
    );
    return _open(client, issued.rootDomain);
  }

  /// Signs out, once this client's writes have reached the atServer or
  /// [syncFor] has passed, and stops the client so that its atSign can be
  /// signed in again.
  Future<void> signOut({Duration syncFor = const Duration(seconds: 30)}) async {
    final client = _invitations?.atClient;
    _invitations = null;
    AtClientManager.getInstance().reset();
    if (client != null) {
      // NOTE: stop() abandons unsynced writes, and this app writes local-first.
      await _syncOut(client).timeout(syncFor, onTimeout: () {});
      await client.stop();
    }
    notifyListeners();
  }

  Future<void> _syncOut(AtClient client) async {
    while (!await client.syncService.isInSync()) {
      if (!client.syncService.isSyncInProgress) client.syncService.sync();
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<bool> _open(AtClient? client, AtRootDomain rootDomain) async {
    if (client == null) return false;
    AtClientManager.getInstance().use(client);
    final atSign = client.getCurrentAtSign()!;
    _rootDomainOf[atSign] = rootDomain;
    final reachable = await client.ensureReachable(invitationsNamespace);
    if (!reachable.isReachable) {
      throw StateError(
        'Other atSigns cannot send to $atSign in $invitationsNamespace '
        '(${reachable.outcome.name})',
      );
    }
    _invitations = AtClientInvitations(
      client,
      invitationsNamespace: invitationsNamespace,
    );
    notifyListeners();
    return true;
  }

  AtClientPreference _preference() =>
      AtClientPreference(posture: PqPosture.pqActive)
        ..namespace = invitationsNamespace;

  /// Where [atSign]'s local store lives: one directory per atSign and root
  /// domain, since the same name under two root domains is two identities.
  ///
  /// With [fresh], anything already there is deleted first. Activation mints
  /// an atSign's keys from scratch, so a store left from an earlier life of
  /// the same atSign, such as a recreated Ephemeral Environment, holds
  /// records sealed under keys that no longer exist.
  Future<HiveAtClientStorage> _storage(
    String atSign,
    AtRootDomain rootDomain, {
    bool fresh = false,
  }) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}/storage/'
      '${rootDomain.rootDomain}_${rootDomain.rootPort}/$atSign',
    );
    if (fresh && dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    return HiveAtClientStorage(
      atSign: atSign,
      storagePath: dir.path,
      closedByClient: true,
    );
  }
}
