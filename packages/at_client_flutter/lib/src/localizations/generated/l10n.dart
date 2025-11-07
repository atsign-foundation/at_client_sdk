// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class AtOnboardingLocalizations {
  AtOnboardingLocalizations();

  static AtOnboardingLocalizations? _current;

  static AtOnboardingLocalizations get current {
    assert(_current != null,
        'No instance of AtOnboardingLocalizations was loaded. Try to initialize the AtOnboardingLocalizations delegate before accessing AtOnboardingLocalizations.current.');
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<AtOnboardingLocalizations> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = AtOnboardingLocalizations();
      AtOnboardingLocalizations._current = instance;

      return instance;
    });
  }

  static AtOnboardingLocalizations of(BuildContext context) {
    final instance = AtOnboardingLocalizations.maybeOf(context);
    assert(instance != null,
        'No instance of AtOnboardingLocalizations present in the widget tree. Did you add AtOnboardingLocalizations.delegate in localizationsDelegates?');
    return instance!;
  }

  static AtOnboardingLocalizations? maybeOf(BuildContext context) {
    return Localizations.of<AtOnboardingLocalizations>(
        context, AtOnboardingLocalizations);
  }

  /// `Select atSigns`
  String get select_atSign {
    return Intl.message(
      'Select atSigns',
      name: 'select_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Loading atSigns`
  String get loading_atSigns {
    return Intl.message(
      'Loading atSigns',
      name: 'loading_atSigns',
      desc: '',
      args: [],
    );
  }

  /// `You already have some existing atsigns. Please select an atSign or else continue with the new one.`
  String get title_select_atSign {
    return Intl.message(
      'You already have some existing atsigns. Please select an atSign or else continue with the new one.',
      name: 'title_select_atSign',
      desc: '',
      args: [],
    );
  }

  /// `You have selected `
  String get title_pair_atSign_prev {
    return Intl.message(
      'You have selected ',
      name: 'title_pair_atSign_prev',
      desc: '',
      args: [],
    );
  }

  /// `to pair with this device`
  String get title_pair_atSign_next {
    return Intl.message(
      'to pair with this device',
      name: 'title_pair_atSign_next',
      desc: '',
      args: [],
    );
  }

  /// `Yes, continue`
  String get btn_yes_continue {
    return Intl.message(
      'Yes, continue',
      name: 'btn_yes_continue',
      desc: '',
      args: [],
    );
  }

  /// `Please wait while fetching atSign status`
  String get msg_wait_fetching_atSign {
    return Intl.message(
      'Please wait while fetching atSign status',
      name: 'msg_wait_fetching_atSign',
      desc: '',
      args: [],
    );
  }

  /// `This atSign has already been activated and paired with this device`
  String get error_atSign_logged {
    return Intl.message(
      'This atSign has already been activated and paired with this device',
      name: 'error_atSign_logged',
      desc: '',
      args: [],
    );
  }

  /// `This atSign has already been activated. Please upload your atKeys to pair it with this device`
  String get error_atSign_activated {
    return Intl.message(
      'This atSign has already been activated. Please upload your atKeys to pair it with this device',
      name: 'error_atSign_activated',
      desc: '',
      args: [],
    );
  }

  /// `Notice`
  String get notice {
    return Intl.message(
      'Notice',
      name: 'notice',
      desc: '',
      args: [],
    );
  }

  /// `Your session expired`
  String get title_session_expired {
    return Intl.message(
      'Your session expired',
      name: 'title_session_expired',
      desc: '',
      args: [],
    );
  }

  /// `Authentication Failed`
  String get error_authenticated_failed {
    return Intl.message(
      'Authentication Failed',
      name: 'error_authenticated_failed',
      desc: '',
      args: [],
    );
  }

  /// `Server not found`
  String get error_server_not_found {
    return Intl.message(
      'Server not found',
      name: 'error_server_not_found',
      desc: '',
      args: [],
    );
  }

  /// `An atSign is required.`
  String get msg_atSign_required {
    return Intl.message(
      'An atSign is required.',
      name: 'msg_atSign_required',
      desc: '',
      args: [],
    );
  }

  /// `CONTINUE`
  String get btn_continue {
    return Intl.message(
      'CONTINUE',
      name: 'btn_continue',
      desc: '',
      args: [],
    );
  }

  /// `Remind Me Later`
  String get btn_remind_me_later {
    return Intl.message(
      'Remind Me Later',
      name: 'btn_remind_me_later',
      desc: '',
      args: [],
    );
  }

  /// `Setting up your atSign`
  String get title_setting_up_your_atSign {
    return Intl.message(
      'Setting up your atSign',
      name: 'title_setting_up_your_atSign',
      desc: '',
      args: [],
    );
  }

  /// `FAQ`
  String get title_FAQ {
    return Intl.message(
      'FAQ',
      name: 'title_FAQ',
      desc: '',
      args: [],
    );
  }

  /// `Your atSign and the server is unreachable. Please try again or contact support@atsign.com`
  String get msg_atSign_unreachable {
    return Intl.message(
      'Your atSign and the server is unreachable. Please try again or contact support@atsign.com',
      name: 'msg_atSign_unreachable',
      desc: '',
      args: [],
    );
  }

  /// `Your atSign is not registered yet. Please try with the registered one.`
  String get msg_atSign_not_registered {
    return Intl.message(
      'Your atSign is not registered yet. Please try with the registered one.',
      name: 'msg_atSign_not_registered',
      desc: '',
      args: [],
    );
  }

  /// `Save your key`
  String get title_save_your_key {
    return Intl.message(
      'Save your key',
      name: 'title_save_your_key',
      desc: '',
      args: [],
    );
  }

  /// `IMPORTANT!`
  String get title_important {
    return Intl.message(
      'IMPORTANT!',
      name: 'title_important',
      desc: '',
      args: [],
    );
  }

  /// `Please save your key in a secure location (we recommend Google Drive or iCloud Drive). You will need it to sign back in AND use other atPlatform apps.`
  String get msg_save_atKey_in_secure_location {
    return Intl.message(
      'Please save your key in a secure location (we recommend Google Drive or iCloud Drive). You will need it to sign back in AND use other atPlatform apps.',
      name: 'msg_save_atKey_in_secure_location',
      desc: '',
      args: [],
    );
  }

  /// `SAVE`
  String get btn_save {
    return Intl.message(
      'SAVE',
      name: 'btn_save',
      desc: '',
      args: [],
    );
  }

  /// `SKIP TUTORIAL`
  String get btn_skip_tutorial {
    return Intl.message(
      'SKIP TUTORIAL',
      name: 'btn_skip_tutorial',
      desc: '',
      args: [],
    );
  }

  /// `Tap to generate a new free atSign`
  String get tutorial_generate_atSign {
    return Intl.message(
      'Tap to generate a new free atSign',
      name: 'tutorial_generate_atSign',
      desc: '',
      args: [],
    );
  }

  /// `If you have an atSign, Tap to upload atSign key`
  String get tutorial_upload_atSign_key {
    return Intl.message(
      'If you have an atSign, Tap to upload atSign key',
      name: 'tutorial_upload_atSign_key',
      desc: '',
      args: [],
    );
  }

  /// `Generate a free atSign`
  String get btn_generate_atSign {
    return Intl.message(
      'Generate a free atSign',
      name: 'btn_generate_atSign',
      desc: '',
      args: [],
    );
  }

  /// `atSign cannot be empty`
  String get msg_atSign_cannot_empty {
    return Intl.message(
      'atSign cannot be empty',
      name: 'msg_atSign_cannot_empty',
      desc: '',
      args: [],
    );
  }

  /// `Refresh until you see an atSign that you like, then press Pair`
  String get msg_refresh_atSign {
    return Intl.message(
      'Refresh until you see an atSign that you like, then press Pair',
      name: 'msg_refresh_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Learn more about atSigns`
  String get learn_about_atSign {
    return Intl.message(
      'Learn more about atSigns',
      name: 'learn_about_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Refresh`
  String get btn_refresh {
    return Intl.message(
      'Refresh',
      name: 'btn_refresh',
      desc: '',
      args: [],
    );
  }

  /// `Pair`
  String get btn_pair {
    return Intl.message(
      'Pair',
      name: 'btn_pair',
      desc: '',
      args: [],
    );
  }

  /// `Already have an atSign?`
  String get btn_already_have_atSign {
    return Intl.message(
      'Already have an atSign?',
      name: 'btn_already_have_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Processing...`
  String get processing {
    return Intl.message(
      'Processing...',
      name: 'processing',
      desc: '',
      args: [],
    );
  }

  /// `Response Time out`
  String get msg_response_time_out {
    return Intl.message(
      'Response Time out',
      name: 'msg_response_time_out',
      desc: '',
      args: [],
    );
  }

  /// `Auth Failed`
  String get msg_auth_failed {
    return Intl.message(
      'Auth Failed',
      name: 'msg_auth_failed',
      desc: '',
      args: [],
    );
  }

  /// `Unable to fetch the keys from chosen file. Please choose correct file`
  String get msg_cannot_fetch_keys_from_chosen_file {
    return Intl.message(
      'Unable to fetch the keys from chosen file. Please choose correct file',
      name: 'msg_cannot_fetch_keys_from_chosen_file',
      desc: '',
      args: [],
    );
  }

  /// `Failed in processing files. Please try again`
  String get error_processing_files {
    return Intl.message(
      'Failed in processing files. Please try again',
      name: 'error_processing_files',
      desc: '',
      args: [],
    );
  }

  /// `If you have an activated atSign, tap to upload your atKeys`
  String get tutorial_upload_your_atKey {
    return Intl.message(
      'If you have an activated atSign, tap to upload your atKeys',
      name: 'tutorial_upload_your_atKey',
      desc: '',
      args: [],
    );
  }

  /// `Tap to scan QR code`
  String get tutorial_scan_QRCode {
    return Intl.message(
      'Tap to scan QR code',
      name: 'tutorial_scan_QRCode',
      desc: '',
      args: [],
    );
  }

  /// `Tap to upload image QR code`
  String get tutorial_upload_image_QRCode {
    return Intl.message(
      'Tap to upload image QR code',
      name: 'tutorial_upload_image_QRCode',
      desc: '',
      args: [],
    );
  }

  /// `Tap here to activate your atSign`
  String get tutorial_activate_your_atSign {
    return Intl.message(
      'Tap here to activate your atSign',
      name: 'tutorial_activate_your_atSign',
      desc: '',
      args: [],
    );
  }

  /// `If you don't have an atSign, tap here to get one`
  String get tutorial_get_atSign {
    return Intl.message(
      'If you don\'t have an atSign, tap here to get one',
      name: 'tutorial_get_atSign',
      desc: '',
      args: [],
    );
  }

  /// `images`
  String get images {
    return Intl.message(
      'images',
      name: 'images',
      desc: '',
      args: [],
    );
  }

  /// `Pair an atSign using your atKeys`
  String get pair_atSign {
    return Intl.message(
      'Pair an atSign using your atKeys',
      name: 'pair_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Upload atKeys`
  String get upload_atKeys {
    return Intl.message(
      'Upload atKeys',
      name: 'upload_atKeys',
      desc: '',
      args: [],
    );
  }

  /// `Upload your atKey file. This file was generated when you activated and paired your atSign and you were prompted to store it in a secure location.`
  String get sub_upload_atKeys {
    return Intl.message(
      'Upload your atKey file. This file was generated when you activated and paired your atSign and you were prompted to store it in a secure location.',
      name: 'sub_upload_atKeys',
      desc: '',
      args: [],
    );
  }

  /// `Have a QR Code?`
  String get have_QRCode {
    return Intl.message(
      'Have a QR Code?',
      name: 'have_QRCode',
      desc: '',
      args: [],
    );
  }

  /// `Scan QR code`
  String get btn_scan_QRCode {
    return Intl.message(
      'Scan QR code',
      name: 'btn_scan_QRCode',
      desc: '',
      args: [],
    );
  }

  /// `Upload QR code`
  String get btn_upload_QRCode {
    return Intl.message(
      'Upload QR code',
      name: 'btn_upload_QRCode',
      desc: '',
      args: [],
    );
  }

  /// `Activate an atSign?`
  String get title_activate_an_atSign {
    return Intl.message(
      'Activate an atSign?',
      name: 'title_activate_an_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Activate atSign`
  String get btn_activate_atSign {
    return Intl.message(
      'Activate atSign',
      name: 'btn_activate_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Get a free atSign`
  String get get_free_atSign {
    return Intl.message(
      'Get a free atSign',
      name: 'get_free_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Incorrect QR file`
  String get error_incorrect_QRFile {
    return Intl.message(
      'Incorrect QR file',
      name: 'error_incorrect_QRFile',
      desc: '',
      args: [],
    );
  }

  /// `Failed to process file`
  String get error_process_file {
    return Intl.message(
      'Failed to process file',
      name: 'error_process_file',
      desc: '',
      args: [],
    );
  }

  /// `Activate an atSign`
  String get activate_an_atSign {
    return Intl.message(
      'Activate an atSign',
      name: 'activate_an_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Enter the atSign you would like to activate`
  String get enter_atSign_need_to_activate {
    return Intl.message(
      'Enter the atSign you would like to activate',
      name: 'enter_atSign_need_to_activate',
      desc: '',
      args: [],
    );
  }

  /// `Activate`
  String get activate {
    return Intl.message(
      'Activate',
      name: 'activate',
      desc: '',
      args: [],
    );
  }

  /// `This app was built on the atPlatform. All atPlatform apps require an atSign. `
  String get title_intro {
    return Intl.message(
      'This app was built on the atPlatform. All atPlatform apps require an atSign. ',
      name: 'title_intro',
      desc: '',
      args: [],
    );
  }

  /// `Learn more`
  String get learn_more {
    return Intl.message(
      'Learn more',
      name: 'learn_more',
      desc: '',
      args: [],
    );
  }

  /// `Already have an atSign`
  String get already_have_an_atSign {
    return Intl.message(
      'Already have an atSign',
      name: 'already_have_an_atSign',
      desc: '',
      args: [],
    );
  }

  /// `Enter Verification Code`
  String get enter_verification_code {
    return Intl.message(
      'Enter Verification Code',
      name: 'enter_verification_code',
      desc: '',
      args: [],
    );
  }

  /// `Verify & Login`
  String get verify_and_login {
    return Intl.message(
      'Verify & Login',
      name: 'verify_and_login',
      desc: '',
      args: [],
    );
  }

  /// `Resend Code`
  String get resend_code {
    return Intl.message(
      'Resend Code',
      name: 'resend_code',
      desc: '',
      args: [],
    );
  }

  /// `Note:`
  String get note {
    return Intl.message(
      'Note:',
      name: 'note',
      desc: '',
      args: [],
    );
  }

  /// ` If you didn't receive our email:\n- Confirm that your email address was entered correctly.\n- Check your spam/junk or promotions folder.`
  String get note_otp_content {
    return Intl.message(
      ' If you didn\'t receive our email:\n- Confirm that your email address was entered correctly.\n- Check your spam/junk or promotions folder.',
      name: 'note_otp_content',
      desc: '',
      args: [],
    );
  }

  /// `Verification code sent to`
  String get verification_code_sent_to {
    return Intl.message(
      'Verification code sent to',
      name: 'verification_code_sent_to',
      desc: '',
      args: [],
    );
  }

  /// `Close`
  String get btn_close {
    return Intl.message(
      'Close',
      name: 'btn_close',
      desc: '',
      args: [],
    );
  }

  /// `Please enter the 4-character verification code that was sent to your email address`
  String get enter_code {
    return Intl.message(
      'Please enter the 4-character verification code that was sent to your email address',
      name: 'enter_code',
      desc: '',
      args: [],
    );
  }

  /// `Oops! You already have the maximum number of free atSigns. Please login to `
  String get msg_maximum_atSign_prev {
    return Intl.message(
      'Oops! You already have the maximum number of free atSigns. Please login to ',
      name: 'msg_maximum_atSign_prev',
      desc: '',
      args: [],
    );
  }

  /// ` to select one of your existing atSigns.`
  String get msg_maximum_atSign_next {
    return Intl.message(
      ' to select one of your existing atSigns.',
      name: 'msg_maximum_atSign_next',
      desc: '',
      args: [],
    );
  }

  /// `Enter your email address`
  String get enter_your_email_address {
    return Intl.message(
      'Enter your email address',
      name: 'enter_your_email_address',
      desc: '',
      args: [],
    );
  }

  /// `Note: We do not share your personal information or use it for financial gain.`
  String get note_pair_content {
    return Intl.message(
      'Note: We do not share your personal information or use it for financial gain.',
      name: 'note_pair_content',
      desc: '',
      args: [],
    );
  }

  /// `Send Code`
  String get send_code {
    return Intl.message(
      'Send Code',
      name: 'send_code',
      desc: '',
      args: [],
    );
  }

  /// `Please enter a valid email address`
  String get error_please_enter_email {
    return Intl.message(
      'Please enter a valid email address',
      name: 'error_please_enter_email',
      desc: '',
      args: [],
    );
  }

  /// `Enter a valid email address`
  String get error_enter_valid_email {
    return Intl.message(
      'Enter a valid email address',
      name: 'error_enter_valid_email',
      desc: '',
      args: [],
    );
  }

  /// `No permission`
  String get no_permission {
    return Intl.message(
      'No permission',
      name: 'no_permission',
      desc: '',
      args: [],
    );
  }

  /// `Scan your QR!`
  String get scan_your_QR {
    return Intl.message(
      'Scan your QR!',
      name: 'scan_your_QR',
      desc: '',
      args: [],
    );
  }

  /// `Invalid QR.`
  String get invalid_QR {
    return Intl.message(
      'Invalid QR.',
      name: 'invalid_QR',
      desc: '',
      args: [],
    );
  }

  /// `Reset`
  String get reset {
    return Intl.message(
      'Reset',
      name: 'reset',
      desc: '',
      args: [],
    );
  }

  /// `This will remove the selected atSign and its details from this app only.`
  String get reset_description {
    return Intl.message(
      'This will remove the selected atSign and its details from this app only.',
      name: 'reset_description',
      desc: '',
      args: [],
    );
  }

  /// `No atSigns are paired to reset. `
  String get no_atSigns_paired_to_reset {
    return Intl.message(
      'No atSigns are paired to reset. ',
      name: 'no_atSigns_paired_to_reset',
      desc: '',
      args: [],
    );
  }

  /// `Select All`
  String get select_all {
    return Intl.message(
      'Select All',
      name: 'select_all',
      desc: '',
      args: [],
    );
  }

  /// `Warning: This action cannot be undone`
  String get msg_action_cannot_undone {
    return Intl.message(
      'Warning: This action cannot be undone',
      name: 'msg_action_cannot_undone',
      desc: '',
      args: [],
    );
  }

  /// `Remove`
  String get remove {
    return Intl.message(
      'Remove',
      name: 'remove',
      desc: '',
      args: [],
    );
  }

  /// `Please select at least one atSign to reset`
  String get select_atSign_to_reset {
    return Intl.message(
      'Please select at least one atSign to reset',
      name: 'select_atSign_to_reset',
      desc: '',
      args: [],
    );
  }

  /// `Onboarding`
  String get onboarding {
    return Intl.message(
      'Onboarding',
      name: 'onboarding',
      desc: '',
      args: [],
    );
  }

  /// `Cancel`
  String get btn_cancel {
    return Intl.message(
      'Cancel',
      name: 'btn_cancel',
      desc: '',
      args: [],
    );
  }

  /// `No`
  String get btn_no {
    return Intl.message(
      'No',
      name: 'btn_no',
      desc: '',
      args: [],
    );
  }

  /// `Yes`
  String get btn_yes {
    return Intl.message(
      'Yes',
      name: 'btn_yes',
      desc: '',
      args: [],
    );
  }

  /// `Do you want to share this onboarded atsign with other apps on atPlatform?`
  String get title_shared_storage {
    return Intl.message(
      'Do you want to share this onboarded atsign with other apps on atPlatform?',
      name: 'title_shared_storage',
      desc: '',
      args: [],
    );
  }

  /// `This would save you the process to onboard this atsign on other apps again.`
  String get msg_shared_storage {
    return Intl.message(
      'This would save you the process to onboard this atsign on other apps again.',
      name: 'msg_shared_storage',
      desc: '',
      args: [],
    );
  }

  /// `A verification code has been sent to`
  String get verification_code_has_been_sent_to {
    return Intl.message(
      'A verification code has been sent to',
      name: 'verification_code_has_been_sent_to',
      desc: '',
      args: [],
    );
  }

  /// `your registered email.`
  String get your_registered_email {
    return Intl.message(
      'your registered email.',
      name: 'your_registered_email',
      desc: '',
      args: [],
    );
  }

  /// `Unable to perform this action. Please try again.`
  String get error_unable_to_perform_this_action {
    return Intl.message(
      'Unable to perform this action. Please try again.',
      name: 'error_unable_to_perform_this_action',
      desc: '',
      args: [],
    );
  }

  /// `Unable to authenticate. Please try again.`
  String get error_unable_to_authenticate {
    return Intl.message(
      'Unable to authenticate. Please try again.',
      name: 'error_unable_to_authenticate',
      desc: '',
      args: [],
    );
  }

  /// `Failed in processing. Please try again.`
  String get error_processing {
    return Intl.message(
      'Failed in processing. Please try again.',
      name: 'error_processing',
      desc: '',
      args: [],
    );
  }

  /// `Unable to connect server. Please try again later.`
  String get error_unable_to_connect_server {
    return Intl.message(
      'Unable to connect server. Please try again later.',
      name: 'error_unable_to_connect_server',
      desc: '',
      args: [],
    );
  }

  /// `Unable to perform read/write operation. Please try again.`
  String get error_perform_operation {
    return Intl.message(
      'Unable to perform read/write operation. Please try again.',
      name: 'error_perform_operation',
      desc: '',
      args: [],
    );
  }

  /// `Unable to activate server. Please contact admin.`
  String get error_activate_server {
    return Intl.message(
      'Unable to activate server. Please contact admin.',
      name: 'error_activate_server',
      desc: '',
      args: [],
    );
  }

  /// `Server is unavailable. Please try again later.`
  String get error_server_unavailable {
    return Intl.message(
      'Server is unavailable. Please try again later.',
      name: 'error_server_unavailable',
      desc: '',
      args: [],
    );
  }

  /// `Unable to connect. Please check with network connection and try again.`
  String get error_unable_connect {
    return Intl.message(
      'Unable to connect. Please check with network connection and try again.',
      name: 'error_unable_connect',
      desc: '',
      args: [],
    );
  }

  /// `Invalid atSign is provided. Please contact admin.`
  String get error_invalid_atSign_provided {
    return Intl.message(
      'Invalid atSign is provided. Please contact admin.',
      name: 'error_invalid_atSign_provided',
      desc: '',
      args: [],
    );
  }

  /// `Please provide valid backup key file to continue.`
  String get error_provide_backupKey {
    return Intl.message(
      'Please provide valid backup key file to continue.',
      name: 'error_provide_backupKey',
      desc: '',
      args: [],
    );
  }

  /// `Please provide a relevant backup key file to authenticate.`
  String get error_provide_relevant_backupKey {
    return Intl.message(
      'Please provide a relevant backup key file to authenticate.',
      name: 'error_provide_relevant_backupKey',
      desc: '',
      args: [],
    );
  }

  /// `Please provide a valid QRCode to authenticate.`
  String get error_provide_valid_QRCode {
    return Intl.message(
      'Please provide a valid QRCode to authenticate.',
      name: 'error_provide_valid_QRCode',
      desc: '',
      args: [],
    );
  }

  /// `Unknown error.`
  String get error_unknown {
    return Intl.message(
      'Unknown error.',
      name: 'error_unknown',
      desc: '',
      args: [],
    );
  }

  /// `Server response timed out!\nPlease check your network connection and try again. Contact {contactAddress} if the issue still persists.`
  String error_server_response_timed_out(Object contactAddress) {
    return Intl.message(
      'Server response timed out!\nPlease check your network connection and try again. Contact $contactAddress if the issue still persists.',
      name: 'error_server_response_timed_out',
      desc: '',
      args: [contactAddress],
    );
  }

  /// `{atsign} was already paired with this device. First delete/reset this atSign from device to add.`
  String error_atSign_already_paired(Object atsign) {
    return Intl.message(
      '$atsign was already paired with this device. First delete/reset this atSign from device to add.',
      name: 'error_atSign_already_paired',
      desc: '',
      args: [atsign],
    );
  }

  /// `atSign mismatches. Please provide the QRCode of {givenAtsign} to pair.`
  String atSign_mismatches_need_to_provide_QRCode(Object givenAtsign) {
    return Intl.message(
      'atSign mismatches. Please provide the QRCode of $givenAtsign to pair.',
      name: 'atSign_mismatches_need_to_provide_QRCode',
      desc: '',
      args: [givenAtsign],
    );
  }

  /// `atSign mismatches. Please provide the backup key file of {givenAtsign} to pair.`
  String atSign_mismatches_need_to_provide_backupKey(Object givenAtsign) {
    return Intl.message(
      'atSign mismatches. Please provide the backup key file of $givenAtsign to pair.',
      name: 'atSign_mismatches_need_to_provide_backupKey',
      desc: '',
      args: [givenAtsign],
    );
  }
}

class AppLocalizationDelegate
    extends LocalizationsDelegate<AtOnboardingLocalizations> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'fr'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<AtOnboardingLocalizations> load(Locale locale) =>
      AtOnboardingLocalizations.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
