// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(givenAtsign) =>
      "atSign mismatches. Please provide the QRCode of ${givenAtsign} to pair.";

  static String m1(givenAtsign) =>
      "atSign mismatches. Please provide the backup key file of ${givenAtsign} to pair.";

  static String m2(atsign) =>
      "${atsign} was already paired with this device. First delete/reset this atSign from device to add.";

  static String m3(contactAddress) =>
      "Server response timed out!\nPlease check your network connection and try again. Contact ${contactAddress} if the issue still persists.";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "activate": MessageLookupByLibrary.simpleMessage("Activate"),
        "activate_an_atSign":
            MessageLookupByLibrary.simpleMessage("Activate an atSign"),
        "already_have_an_atSign":
            MessageLookupByLibrary.simpleMessage("Already have an atSign"),
        "atSign_mismatches_need_to_provide_QRCode": m0,
        "atSign_mismatches_need_to_provide_backupKey": m1,
        "btn_activate_atSign":
            MessageLookupByLibrary.simpleMessage("Activate atSign"),
        "btn_already_have_atSign":
            MessageLookupByLibrary.simpleMessage("Already have an atSign?"),
        "btn_cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
        "btn_close": MessageLookupByLibrary.simpleMessage("Close"),
        "btn_continue": MessageLookupByLibrary.simpleMessage("CONTINUE"),
        "btn_generate_atSign":
            MessageLookupByLibrary.simpleMessage("Generate a free atSign"),
        "btn_no": MessageLookupByLibrary.simpleMessage("No"),
        "btn_pair": MessageLookupByLibrary.simpleMessage("Pair"),
        "btn_refresh": MessageLookupByLibrary.simpleMessage("Refresh"),
        "btn_remind_me_later":
            MessageLookupByLibrary.simpleMessage("Remind Me Later"),
        "btn_save": MessageLookupByLibrary.simpleMessage("SAVE"),
        "btn_scan_QRCode": MessageLookupByLibrary.simpleMessage("Scan QR code"),
        "btn_skip_tutorial":
            MessageLookupByLibrary.simpleMessage("SKIP TUTORIAL"),
        "btn_upload_QRCode":
            MessageLookupByLibrary.simpleMessage("Upload QR code"),
        "btn_yes": MessageLookupByLibrary.simpleMessage("Yes"),
        "btn_yes_continue":
            MessageLookupByLibrary.simpleMessage("Yes, continue"),
        "enter_atSign_need_to_activate": MessageLookupByLibrary.simpleMessage(
            "Enter the atSign you would like to activate"),
        "enter_code": MessageLookupByLibrary.simpleMessage(
            "Please enter the 4-character verification code that was sent to your email address"),
        "enter_verification_code":
            MessageLookupByLibrary.simpleMessage("Enter Verification Code"),
        "enter_your_email_address":
            MessageLookupByLibrary.simpleMessage("Enter your email address"),
        "error_activate_server": MessageLookupByLibrary.simpleMessage(
            "Unable to activate server. Please contact admin."),
        "error_atSign_activated": MessageLookupByLibrary.simpleMessage(
            "This atSign has already been activated. Please upload your atKeys to pair it with this device"),
        "error_atSign_already_paired": m2,
        "error_atSign_logged": MessageLookupByLibrary.simpleMessage(
            "This atSign has already been activated and paired with this device"),
        "error_authenticated_failed":
            MessageLookupByLibrary.simpleMessage("Authentication Failed"),
        "error_enter_valid_email":
            MessageLookupByLibrary.simpleMessage("Enter a valid email address"),
        "error_incorrect_QRFile":
            MessageLookupByLibrary.simpleMessage("Incorrect QR file"),
        "error_invalid_atSign_provided": MessageLookupByLibrary.simpleMessage(
            "Invalid atSign is provided. Please contact admin."),
        "error_perform_operation": MessageLookupByLibrary.simpleMessage(
            "Unable to perform read/write operation. Please try again."),
        "error_please_enter_email": MessageLookupByLibrary.simpleMessage(
            "Please enter a valid email address"),
        "error_process_file":
            MessageLookupByLibrary.simpleMessage("Failed to process file"),
        "error_processing": MessageLookupByLibrary.simpleMessage(
            "Failed in processing. Please try again."),
        "error_processing_files": MessageLookupByLibrary.simpleMessage(
            "Failed in processing files. Please try again"),
        "error_provide_backupKey": MessageLookupByLibrary.simpleMessage(
            "Please provide valid backup key file to continue."),
        "error_provide_relevant_backupKey":
            MessageLookupByLibrary.simpleMessage(
                "Please provide a relevant backup key file to authenticate."),
        "error_provide_valid_QRCode": MessageLookupByLibrary.simpleMessage(
            "Please provide a valid QRCode to authenticate."),
        "error_server_not_found":
            MessageLookupByLibrary.simpleMessage("Server not found"),
        "error_server_response_timed_out": m3,
        "error_server_unavailable": MessageLookupByLibrary.simpleMessage(
            "Server is unavailable. Please try again later."),
        "error_unable_connect": MessageLookupByLibrary.simpleMessage(
            "Unable to connect. Please check with network connection and try again."),
        "error_unable_to_authenticate": MessageLookupByLibrary.simpleMessage(
            "Unable to authenticate. Please try again."),
        "error_unable_to_connect_server": MessageLookupByLibrary.simpleMessage(
            "Unable to connect server. Please try again later."),
        "error_unable_to_perform_this_action":
            MessageLookupByLibrary.simpleMessage(
                "Unable to perform this action. Please try again."),
        "error_unknown": MessageLookupByLibrary.simpleMessage("Unknown error."),
        "get_free_atSign":
            MessageLookupByLibrary.simpleMessage("Get a free atSign"),
        "have_QRCode": MessageLookupByLibrary.simpleMessage("Have a QR Code?"),
        "images": MessageLookupByLibrary.simpleMessage("images"),
        "invalid_QR": MessageLookupByLibrary.simpleMessage("Invalid QR."),
        "learn_about_atSign":
            MessageLookupByLibrary.simpleMessage("Learn more about atSigns"),
        "learn_more": MessageLookupByLibrary.simpleMessage("Learn more"),
        "loading_atSigns":
            MessageLookupByLibrary.simpleMessage("Loading atSigns"),
        "msg_action_cannot_undone": MessageLookupByLibrary.simpleMessage(
            "Warning: This action cannot be undone"),
        "msg_atSign_cannot_empty":
            MessageLookupByLibrary.simpleMessage("atSign cannot be empty"),
        "msg_atSign_not_registered": MessageLookupByLibrary.simpleMessage(
            "Your atSign is not registered yet. Please try with the registered one."),
        "msg_atSign_required":
            MessageLookupByLibrary.simpleMessage("An atSign is required."),
        "msg_atSign_unreachable": MessageLookupByLibrary.simpleMessage(
            "Your atSign and the server is unreachable. Please try again or contact support@atsign.com"),
        "msg_auth_failed": MessageLookupByLibrary.simpleMessage("Auth Failed"),
        "msg_cannot_fetch_keys_from_chosen_file":
            MessageLookupByLibrary.simpleMessage(
                "Unable to fetch the keys from chosen file. Please choose correct file"),
        "msg_maximum_atSign_next": MessageLookupByLibrary.simpleMessage(
            " to select one of your existing atSigns."),
        "msg_maximum_atSign_prev": MessageLookupByLibrary.simpleMessage(
            "Oops! You already have the maximum number of free atSigns. Please login to "),
        "msg_refresh_atSign": MessageLookupByLibrary.simpleMessage(
            "Refresh until you see an atSign that you like, then press Pair"),
        "msg_response_time_out":
            MessageLookupByLibrary.simpleMessage("Response Time out"),
        "msg_save_atKey_in_secure_location": MessageLookupByLibrary.simpleMessage(
            "Please save your key in a secure location (we recommend Google Drive or iCloud Drive). You will need it to sign back in AND use other atPlatform apps."),
        "msg_shared_storage": MessageLookupByLibrary.simpleMessage(
            "This would save you the process to onboard this atsign on other apps again."),
        "msg_wait_fetching_atSign": MessageLookupByLibrary.simpleMessage(
            "Please wait while fetching atSign status"),
        "no_atSigns_paired_to_reset": MessageLookupByLibrary.simpleMessage(
            "No atSigns are paired to reset. "),
        "no_permission": MessageLookupByLibrary.simpleMessage("No permission"),
        "note": MessageLookupByLibrary.simpleMessage("Note:"),
        "note_otp_content": MessageLookupByLibrary.simpleMessage(
            " If you didn\'t receive our email:\n- Confirm that your email address was entered correctly.\n- Check your spam/junk or promotions folder."),
        "note_pair_content": MessageLookupByLibrary.simpleMessage(
            "Note: We do not share your personal information or use it for financial gain."),
        "notice": MessageLookupByLibrary.simpleMessage("Notice"),
        "onboarding": MessageLookupByLibrary.simpleMessage("Onboarding"),
        "pair_atSign": MessageLookupByLibrary.simpleMessage(
            "Pair an atSign using your atKeys"),
        "processing": MessageLookupByLibrary.simpleMessage("Processing..."),
        "remove": MessageLookupByLibrary.simpleMessage("Remove"),
        "resend_code": MessageLookupByLibrary.simpleMessage("Resend Code"),
        "reset": MessageLookupByLibrary.simpleMessage("Reset"),
        "reset_description": MessageLookupByLibrary.simpleMessage(
            "This will remove the selected atSign and its details from this app only."),
        "scan_your_QR": MessageLookupByLibrary.simpleMessage("Scan your QR!"),
        "select_all": MessageLookupByLibrary.simpleMessage("Select All"),
        "select_atSign": MessageLookupByLibrary.simpleMessage("Select atSigns"),
        "select_atSign_to_reset": MessageLookupByLibrary.simpleMessage(
            "Please select at least one atSign to reset"),
        "send_code": MessageLookupByLibrary.simpleMessage("Send Code"),
        "sub_upload_atKeys": MessageLookupByLibrary.simpleMessage(
            "Upload your atKey file. This file was generated when you activated and paired your atSign and you were prompted to store it in a secure location."),
        "title_FAQ": MessageLookupByLibrary.simpleMessage("FAQ"),
        "title_activate_an_atSign":
            MessageLookupByLibrary.simpleMessage("Activate an atSign?"),
        "title_important": MessageLookupByLibrary.simpleMessage("IMPORTANT!"),
        "title_intro": MessageLookupByLibrary.simpleMessage(
            "This app was built on the atPlatform. All atPlatform apps require an atSign. "),
        "title_pair_atSign_next":
            MessageLookupByLibrary.simpleMessage("to pair with this device"),
        "title_pair_atSign_prev":
            MessageLookupByLibrary.simpleMessage("You have selected "),
        "title_save_your_key":
            MessageLookupByLibrary.simpleMessage("Save your key"),
        "title_select_atSign": MessageLookupByLibrary.simpleMessage(
            "You already have some existing atsigns. Please select an atSign or else continue with the new one."),
        "title_session_expired":
            MessageLookupByLibrary.simpleMessage("Your session expired"),
        "title_setting_up_your_atSign":
            MessageLookupByLibrary.simpleMessage("Setting up your atSign"),
        "title_shared_storage": MessageLookupByLibrary.simpleMessage(
            "Do you want to share this onboarded atsign with other apps on atPlatform?"),
        "tutorial_activate_your_atSign": MessageLookupByLibrary.simpleMessage(
            "Tap here to activate your atSign"),
        "tutorial_generate_atSign": MessageLookupByLibrary.simpleMessage(
            "Tap to generate a new free atSign"),
        "tutorial_get_atSign": MessageLookupByLibrary.simpleMessage(
            "If you don\'t have an atSign, tap here to get one"),
        "tutorial_scan_QRCode":
            MessageLookupByLibrary.simpleMessage("Tap to scan QR code"),
        "tutorial_upload_atSign_key": MessageLookupByLibrary.simpleMessage(
            "If you have an atSign, Tap to upload atSign key"),
        "tutorial_upload_image_QRCode":
            MessageLookupByLibrary.simpleMessage("Tap to upload image QR code"),
        "tutorial_upload_your_atKey": MessageLookupByLibrary.simpleMessage(
            "If you have an activated atSign, tap to upload your atKeys"),
        "upload_atKeys": MessageLookupByLibrary.simpleMessage("Upload atKeys"),
        "verification_code_has_been_sent_to":
            MessageLookupByLibrary.simpleMessage(
                "A verification code has been sent to"),
        "verification_code_sent_to":
            MessageLookupByLibrary.simpleMessage("Verification code sent to"),
        "verify_and_login":
            MessageLookupByLibrary.simpleMessage("Verify & Login"),
        "your_registered_email":
            MessageLookupByLibrary.simpleMessage("your registered email.")
      };
}
