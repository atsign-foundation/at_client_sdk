import 'dart:async';

import 'package:at_client_mobile/at_client_mobile.dart';

import 'onboarding_service.dart';

class SDKService {
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  Map<String?, AtAuthService>? atClientServiceMap = <String?, AtAuthService>{};
  List<String>? atSignsList;
  String? currentAtsign;
  String? lastOnboardedAtsign;
  Map<String?, bool>? monitorConnectionMap = <String?, bool>{};

  static final SDKService _singleton = SDKService._internal();
  SDKService._internal();

  factory SDKService() {
    return _singleton;
  }

  ///Returns [atsign]'s atClient instance.
  ///If [atsign] is null then it will be current @sign.
  AtClient _getAtClientForAtsign() {
    return AtClientManager.getInstance().atClient;
  }

  ///Fetches atsign from device keychain.
  Future<String?> getAtSign() async {
    return _keyChainManager.getAtSign();
  }

  ///Deletes the [atsign] from device storage.
  Future<void> deleteAtSign(String atsign) async {
    await _keyChainManager.deleteAtSignFromKeychain(atsign);
    atClientServiceMap!.remove(atsign);
    monitorConnectionMap!.remove(atsign);
    if (atsign == currentAtsign) currentAtsign = null;
    if (atsign == lastOnboardedAtsign) lastOnboardedAtsign = null;
    atSignsList!.remove(atsign);
  }

  ///Returns list of atsigns stored in device storage.
  Future<List<String>?> getAtsignList() async {
    atSignsList = await _keyChainManager.getAtSignListFromKeychain();
    return atSignsList;
  }

  ///Makes [atsign] as primary in device storage and returns `true` for successful change.
  Future<bool> makeAtSignPrimary(String atsign) async {
    return _keyChainManager.makeAtSignPrimary(atsign);
  }

  ///Returns `true` on updating [atKey] with [value] for current @sign.
  Future<bool> put(AtKey atKey, dynamic value) async {
    return _getAtClientForAtsign().put(atKey, value);
  }

  ///Returns `true` on deleting [atKey] for current @sign.
  Future<bool> delete(AtKey atKey) async {
    return _getAtClientForAtsign().delete(atKey);
  }

  ///Resets [atsigns] list from device storage.
  Future<void> resetAtsigns(List<String> atsigns) async {
    for (String atsign in atsigns) {
      await _keyChainManager.resetAtSignFromKeychain(atsign);
      // Hint: Since, the OnboardingService is a singleton instance. Setting
      // atSign to null to enable setting new atSign during subsequent
      // onboard process.
      OnboardingService.getInstance().setAtsign = null;
      atClientServiceMap!.remove(atsign);
      monitorConnectionMap!.remove(atsign);
    }
    currentAtsign = null;
    lastOnboardedAtsign = null;
    atSignsList = [];
  }

  ///Returns `true` if [atsign] is onboarded in the app.
  bool isOnboarded(String atsign) {
    return atClientServiceMap!.containsKey(atsign);
  }

  void sync() {
    // ignore: deprecated_member_use
    AtClientManager.getInstance().syncService.sync();
  }

  ///Returns null if [atsign] is null else the formatted [atsign].
  ///[atsign] must be non-null.
  String formatAtSign(String atsign) {
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    atsign = !atsign.startsWith('@') ? '@$atsign' : atsign;
    return atsign;
  }
}
