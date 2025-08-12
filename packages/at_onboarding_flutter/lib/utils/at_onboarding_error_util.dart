import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_onboarding_flutter/localizations/generated/l10n.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_app_constants.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_response_status.dart';
import 'package:at_server_status/at_server_status.dart';

class AtOnboardingErrorToString {
  String getErrorMessage(dynamic error) {
    OnboardingService onboardingService = OnboardingService.getInstance();
    switch (error.runtimeType) {
      case AtClientException:
        return AtOnboardingLocalizations
            .current.error_unable_to_perform_this_action;
      case UnAuthenticatedException:
        return AtOnboardingLocalizations.current.error_unable_to_authenticate;
      case NoSuchMethodError:
        return AtOnboardingLocalizations.current.error_processing;
      case AtConnectException:
        return AtOnboardingLocalizations.current.error_unable_to_connect_server;
      case AtIOException:
        return AtOnboardingLocalizations.current.error_perform_operation;
      case AtServerException:
        return AtOnboardingLocalizations.current.error_activate_server;
      case SecondaryNotFoundException:
        return AtOnboardingLocalizations.current.error_server_unavailable;
      case SecondaryConnectException:
        return AtOnboardingLocalizations.current.error_unable_connect;
      case InvalidAtSignException:
        return AtOnboardingLocalizations.current.error_invalid_atSign_provided;
      case ServerStatus:
        return _getServerStatusMessage(error);
      case OnboardingStatus:
        return error.toString();
      case AtOnboardingResponseStatus:
        if (error == AtOnboardingResponseStatus.authFailed) {
          if (onboardingService.isPkam!) {
            return AtOnboardingLocalizations.current.error_provide_backupKey;
          } else {
            return onboardingService.serverStatus == ServerStatus.activated
                ? AtOnboardingLocalizations
                    .current.error_provide_relevant_backupKey
                : AtOnboardingLocalizations.current.error_provide_valid_QRCode;
          }
        } else if (error == AtOnboardingResponseStatus.timeOut) {
          return AtOnboardingLocalizations.current
              .error_server_response_timed_out(
                  AtOnboardingConstants.contactAddress);
        } else {
          return '';
        }
      case String:
        return error;
      default:
        return AtOnboardingLocalizations.current.error_unknown;
    }
  }

  String _getServerStatusMessage(ServerStatus? message) {
    switch (message) {
      case ServerStatus.unavailable:
      case ServerStatus.stopped:
        return AtOnboardingLocalizations.current.error_server_unavailable;
      case ServerStatus.error:
        return AtOnboardingLocalizations.current.error_unable_connect;
      default:
        return '';
    }
  }

  String pairedAtsign(String? atsign) =>
      AtOnboardingLocalizations.current.error_atSign_already_paired('$atsign');

  String atsignMismatch(String? givenAtsign, {bool isQr = false}) {
    if (isQr) {
      return AtOnboardingLocalizations.current
          .atSign_mismatches_need_to_provide_QRCode('$givenAtsign');
    } else {
      return AtOnboardingLocalizations.current
          .atSign_mismatches_need_to_provide_backupKey('$givenAtsign');
    }
  }
}
