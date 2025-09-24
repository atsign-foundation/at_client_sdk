import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final atOnboardingService =
    StateNotifierProvider<AtOnboardingService, AsyncValue<List<String?>>>(
  (ref) => AtOnboardingService(ref: ref),
);

class AtOnboardingService extends StateNotifier<AsyncValue<List<String?>>> {
  final Ref ref;
  AtOnboardingService({required this.ref}) : super(const AsyncValue.loading());

  AtOnboardingStatusStream get _progressController =>
      ref.read(atAuthServiceProvider).onboardingStatusStream;
  Stream<AtOnboardingStatusEvent> get progressStream =>
      _progressController.stream;

  Future<AtOnboardingStatus> onboard(
    AtOnboardingRequest atOnboardingRequest, {
    String? cramSecret,
    String? registrarUrl,
  }) async {
    Completer<AtOnboardingStatus> completer = Completer<AtOnboardingStatus>();
    atOnboardingRequest.deviceName ??=
        atOnboardingRequest.deviceName ?? 'default-device';
    atOnboardingRequest.appName ??= atOnboardingRequest.appName ?? 'system';
    var isOnboarded = await ref
        .read(atAuthServiceProvider)
        .isOnboarded(atOnboardingRequest.atSign);
        
    if (isOnboarded) {
      var request = AtAuthRequest(atOnboardingRequest.atSign)
        ..rootDomain = atOnboardingRequest.rootDomain;
      return authenticate(request);
    }

    AtOnboardingResponse response;
    try {
      response = await ref
          .watch(atAuthServiceProvider)
          .onboard(atOnboardingRequest, cramSecret: cramSecret, registrarUrl: registrarUrl);
    } catch (e, s) {
      _progressController.add(AtOnboardingStatusError(
          'Onboarding failed for ${atOnboardingRequest.atSign}, $e \n $s',
          AtOnboardingStatus.authFailed));
      completer.complete(AtOnboardingStatus.authFailed);
      return completer.future;
    }
    if (response.isSuccessful) {
      _progressController.add(AtOnboardingStatusSuccess());
      completer.complete(AtOnboardingStatus.authSuccess);
    } else {
      _progressController.add(AtOnboardingStatusError(
          'Onboarding failed for ${atOnboardingRequest.atSign}',
          AtOnboardingStatus.authFailed));
      completer.complete(AtOnboardingStatus.authFailed);
    }
    return completer.future;
  }

  Future<AtOnboardingStatus> authenticate(AtAuthRequest atAuthRequest) async {
    Completer<AtOnboardingStatus> completer = Completer<AtOnboardingStatus>();
    var status = await ref
        .read(atAuthServiceProvider)
        .checkAtSignServerStatus(atAuthRequest.atSign);
    if (status != ServerStatus.unavailable || status == ServerStatus.teapot) {
      _progressController.add(AtOnboardingStatusError(
          'AtSign ${atAuthRequest.atSign} not found in root domain ${atAuthRequest.rootDomain.rootDomain}:${atAuthRequest.rootDomain.rootPort}',
          AtOnboardingStatus.serverNotReached));
      completer.complete(AtOnboardingStatus.serverNotReached);
      return completer.future;
    }
    AtAuthResponse response;
    try {
      response =
          await ref.watch(atAuthServiceProvider).authenticate(atAuthRequest);
    } catch (e, s) {
      _progressController.add(AtOnboardingStatusError(
          'Authentication failed for ${atAuthRequest.atSign}, $e \n $s',
          AtOnboardingStatus.authFailed));
      completer.complete(AtOnboardingStatus.authFailed);
      return completer.future;
    }
    if (response.isSuccessful) {
      completer.complete(AtOnboardingStatus.authSuccess);
      _progressController.add(AtOnboardingStatusSuccess());
    } else {
      completer.complete(AtOnboardingStatus.authFailed);
      _progressController.add(AtOnboardingStatusError(
          'Authentication failed for ${atAuthRequest.atSign}',
          AtOnboardingStatus.authFailed));
    }
    return completer.future;
  }

  Future<AtEnrollmentResponse> enroll(
      EnrollmentRequest enrollmentRequest) async {
    return await ref.watch(atAuthServiceProvider).enroll(enrollmentRequest);
  }

  Future<List<String?>> getAtSignList() async {
    return await ref.watch(atAuthServiceProvider).getAllAtsigns().then((value) {
      state = AsyncValue.data(value);
      return value;
    }).catchError((error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return [];
    });
  }

  Future<ServerStatus?> checkAtsignStatus(String atsign) async {
    return await ref
        .watch(atAuthServiceProvider)
        .checkAtSignServerStatus(atsign);
  }

  String getAtSign() {
    return ref.watch(atAuthServiceProvider).currentAtSign ?? '';
  }

  void setAtsign(String atsign) {
    ref.watch(atAuthServiceProvider).currentAtSign = atsign;
  }

  AtClientPreference? getAtClientPreference() {
    return ref.watch(atAuthServiceProvider).atClientPreference;
  }

  void setAtClientPreference(AtClientPreference? atClientPreference) {
    ref.watch(atAuthServiceProvider).atClientPreference = atClientPreference;
  }

  Future<bool> isExistingAtsign(String atsign) async {
    return await ref.watch(atAuthServiceProvider).isExistingAtsign(atsign);
  }
}
