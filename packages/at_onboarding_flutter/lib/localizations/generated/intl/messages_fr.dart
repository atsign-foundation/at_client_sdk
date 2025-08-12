// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a fr locale. All the
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
  String get localeName => 'fr';

  static String m0(givenAtsign) =>
      "incompatibilités atSign. Veuillez fournir le QRCode de ${givenAtsign} à coupler.";

  static String m1(givenAtsign) =>
      "incompatibilités atSign. Veuillez fournir le fichier de clé de sauvegarde de ${givenAtsign} à coupler.";

  static String m2(atsign) =>
      "${atsign} était déjà associé à cet appareil. Supprimez/réinitialisez d\'abord cet atSign de l\'appareil à ajouter.";

  static String m3(contactAddress) =>
      "La réponse du serveur a expiré!\nVeuillez vérifier votre connexion réseau et réessayer. Contactez ${contactAddress} si le problème persiste.";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "activate": MessageLookupByLibrary.simpleMessage("Activer"),
        "activate_an_atSign":
            MessageLookupByLibrary.simpleMessage("Activer un atSign"),
        "already_have_an_atSign":
            MessageLookupByLibrary.simpleMessage("A déjà un arobase"),
        "atSign_mismatches_need_to_provide_QRCode": m0,
        "atSign_mismatches_need_to_provide_backupKey": m1,
        "btn_activate_atSign":
            MessageLookupByLibrary.simpleMessage("Activer atSign"),
        "btn_already_have_atSign":
            MessageLookupByLibrary.simpleMessage("Vous avez déjà un atSign?"),
        "btn_cancel": MessageLookupByLibrary.simpleMessage("Annuler"),
        "btn_close": MessageLookupByLibrary.simpleMessage("Fermer"),
        "btn_continue": MessageLookupByLibrary.simpleMessage("CONTINUE"),
        "btn_generate_atSign":
            MessageLookupByLibrary.simpleMessage("Générer un atSign gratuit"),
        "btn_no": MessageLookupByLibrary.simpleMessage("Non"),
        "btn_pair": MessageLookupByLibrary.simpleMessage("Coupler"),
        "btn_refresh": MessageLookupByLibrary.simpleMessage("Actualiser"),
        "btn_remind_me_later":
            MessageLookupByLibrary.simpleMessage("Me rappeler plus tard"),
        "btn_save": MessageLookupByLibrary.simpleMessage("SAUVEGARDER"),
        "btn_scan_QRCode":
            MessageLookupByLibrary.simpleMessage("Scanner le code QR"),
        "btn_skip_tutorial":
            MessageLookupByLibrary.simpleMessage("PASSER LE TUTORIEL"),
        "btn_upload_QRCode":
            MessageLookupByLibrary.simpleMessage("Télécharger le code QR"),
        "btn_yes": MessageLookupByLibrary.simpleMessage("Oui"),
        "btn_yes_continue":
            MessageLookupByLibrary.simpleMessage("Oui, continuer"),
        "enter_atSign_need_to_activate": MessageLookupByLibrary.simpleMessage(
            "Entrez l\'atSign que vous souhaitez activer"),
        "enter_code": MessageLookupByLibrary.simpleMessage(
            "Veuillez entrer le code de vérification à 4 caractères qui a été envoyé à votre adresse e-mail"),
        "enter_verification_code": MessageLookupByLibrary.simpleMessage(
            "Entrez le code de vérification"),
        "enter_your_email_address":
            MessageLookupByLibrary.simpleMessage("Entrez votre adresse e-mail"),
        "error_activate_server": MessageLookupByLibrary.simpleMessage(
            "Impossible d\'activer le serveur. Veuillez contacter l\'administrateur."),
        "error_atSign_activated": MessageLookupByLibrary.simpleMessage(
            "Cet atSign a déjà été activé. Veuillez télécharger vos atKeys pour les coupler avec cet appareil"),
        "error_atSign_already_paired": m2,
        "error_atSign_logged": MessageLookupByLibrary.simpleMessage(
            "Cet atSign a déjà été activé et couplé avec cet appareil"),
        "error_authenticated_failed": MessageLookupByLibrary.simpleMessage(
            "Échec de l\'authentification"),
        "error_enter_valid_email": MessageLookupByLibrary.simpleMessage(
            "Entrez une adresse email valide"),
        "error_incorrect_QRFile":
            MessageLookupByLibrary.simpleMessage("Fichier QR incorrect"),
        "error_invalid_atSign_provided": MessageLookupByLibrary.simpleMessage(
            "Un atSign non valide est fourni. Veuillez contacter l\'administrateur."),
        "error_perform_operation": MessageLookupByLibrary.simpleMessage(
            "Impossible d\'effectuer une opération de lecture/écriture. Veuillez réessayer."),
        "error_please_enter_email": MessageLookupByLibrary.simpleMessage(
            "S\'il vous plaît, mettez une adresse email valide"),
        "error_process_file": MessageLookupByLibrary.simpleMessage(
            "Échec du traitement du fichier"),
        "error_processing": MessageLookupByLibrary.simpleMessage(
            "Échec du traitement. Veuillez réessayer."),
        "error_processing_files": MessageLookupByLibrary.simpleMessage(
            "Échec du traitement des fichiers. Veuillez réessayer"),
        "error_provide_backupKey": MessageLookupByLibrary.simpleMessage(
            "Veuillez fournir un fichier de clé de sauvegarde valide pour continuer."),
        "error_provide_relevant_backupKey": MessageLookupByLibrary.simpleMessage(
            "Veuillez fournir un fichier de clé de sauvegarde pertinent pour vous authentifier."),
        "error_provide_valid_QRCode": MessageLookupByLibrary.simpleMessage(
            "Veuillez fournir un QRCode valide pour vous authentifier."),
        "error_server_not_found":
            MessageLookupByLibrary.simpleMessage("Serveur introuvable"),
        "error_server_response_timed_out": m3,
        "error_server_unavailable": MessageLookupByLibrary.simpleMessage(
            "Le serveur est indisponible. Veuillez réessayer plus tard."),
        "error_unable_connect": MessageLookupByLibrary.simpleMessage(
            "Impossible de se connecter. Veuillez vérifier la connexion réseau et réessayer."),
        "error_unable_to_authenticate": MessageLookupByLibrary.simpleMessage(
            "Impossible à authentifier. Veuillez réessayer."),
        "error_unable_to_connect_server": MessageLookupByLibrary.simpleMessage(
            "Impossible de se connecter au serveur. Veuillez réessayer plus tard."),
        "error_unable_to_perform_this_action":
            MessageLookupByLibrary.simpleMessage(
                "Impossible d\'effectuer cette action. Veuillez réessayer."),
        "error_unknown":
            MessageLookupByLibrary.simpleMessage("Erreur inconnue."),
        "get_free_atSign":
            MessageLookupByLibrary.simpleMessage("Obtenez un atSign gratuit"),
        "have_QRCode":
            MessageLookupByLibrary.simpleMessage("Vous avez un code QR?"),
        "images": MessageLookupByLibrary.simpleMessage("images"),
        "invalid_QR": MessageLookupByLibrary.simpleMessage("QR non valide."),
        "learn_about_atSign":
            MessageLookupByLibrary.simpleMessage("En savoir plus sur atSigns"),
        "learn_more": MessageLookupByLibrary.simpleMessage("En savoir plus"),
        "loading_atSigns":
            MessageLookupByLibrary.simpleMessage("Chargement des atSigns"),
        "msg_action_cannot_undone": MessageLookupByLibrary.simpleMessage(
            "Attention: Cette action ne peut pas être annulée"),
        "msg_atSign_cannot_empty": MessageLookupByLibrary.simpleMessage(
            "atSign ne peut pas être vide"),
        "msg_atSign_not_registered": MessageLookupByLibrary.simpleMessage(
            "Votre atSign n\'est pas encore enregistré. Veuillez essayer avec celui enregistré."),
        "msg_atSign_required":
            MessageLookupByLibrary.simpleMessage("Un atSign est requis."),
        "msg_atSign_unreachable": MessageLookupByLibrary.simpleMessage(
            "Votre atSign et le serveur sont inaccessibles. Veuillez réessayer ou contacter support@atsign.com"),
        "msg_auth_failed": MessageLookupByLibrary.simpleMessage(
            "Echec de l\'authentification"),
        "msg_cannot_fetch_keys_from_chosen_file":
            MessageLookupByLibrary.simpleMessage(
                "Impossible de récupérer les clés du fichier choisi. Veuillez choisir le bon fichier"),
        "msg_maximum_atSign_next": MessageLookupByLibrary.simpleMessage(
            " pour sélectionner l\'un de vos atSigns existants."),
        "msg_maximum_atSign_prev": MessageLookupByLibrary.simpleMessage(
            "Oops! Vous avez déjà le nombre maximum d\'atSigns gratuits. Veuillez vous connecter à "),
        "msg_refresh_atSign": MessageLookupByLibrary.simpleMessage(
            "Actualiser jusqu\'à ce que vous voyiez un atSign que vous aimez, puis appuyez sur Coupler"),
        "msg_response_time_out":
            MessageLookupByLibrary.simpleMessage("Délai de réponse expiré"),
        "msg_save_atKey_in_secure_location": MessageLookupByLibrary.simpleMessage(
            "Veuillez enregistrer votre clé dans un emplacement sécurisé (nous recommandons Google Drive ou iCloud Drive). Vous en aurez besoin pour vous reconnecter ET utiliser d\'autres applications atPlatform."),
        "msg_shared_storage": MessageLookupByLibrary.simpleMessage(
            "Cela vous éviterait d\'avoir à intégrer à nouveau cet atsign sur d\'autres applications."),
        "msg_wait_fetching_atSign": MessageLookupByLibrary.simpleMessage(
            "Veuillez patienter pendant la récupération du statut atSign"),
        "no_atSigns_paired_to_reset": MessageLookupByLibrary.simpleMessage(
            "Aucun atSign n\'est associé à la réinitialisation. "),
        "no_permission":
            MessageLookupByLibrary.simpleMessage("Aucune autorisation"),
        "note": MessageLookupByLibrary.simpleMessage("Remarque:"),
        "note_otp_content": MessageLookupByLibrary.simpleMessage(
            " Si vous n\'avez pas reçu notre e-mail: \n- Confirmez que votre adresse e-mail a été saisie correctement.\n- Vérifiez votre dossier spam/junk ou promotions."),
        "note_pair_content": MessageLookupByLibrary.simpleMessage(
            "Remarque: Nous ne partageons pas vos informations personnelles et ne les utilisons pas à des fins financières."),
        "notice": MessageLookupByLibrary.simpleMessage("Avis"),
        "onboarding": MessageLookupByLibrary.simpleMessage("Intégration"),
        "pair_atSign": MessageLookupByLibrary.simpleMessage(
            "Associer un atSign à l\'aide de vos atKeys"),
        "processing": MessageLookupByLibrary.simpleMessage("Traitement..."),
        "remove": MessageLookupByLibrary.simpleMessage("Supprimer"),
        "resend_code": MessageLookupByLibrary.simpleMessage("Renvoyer le code"),
        "reset": MessageLookupByLibrary.simpleMessage("Réinitialiser"),
        "reset_description": MessageLookupByLibrary.simpleMessage(
            "Cela supprimera l\'atSign sélectionné et ses détails de cette application uniquement."),
        "scan_your_QR":
            MessageLookupByLibrary.simpleMessage("Scannez votre QR!"),
        "select_all": MessageLookupByLibrary.simpleMessage("Sélectionner tout"),
        "select_atSign":
            MessageLookupByLibrary.simpleMessage("Selectionnez  un atSign"),
        "select_atSign_to_reset": MessageLookupByLibrary.simpleMessage(
            "Veuillez sélectionner au moins un atSign à réinitialiser"),
        "send_code": MessageLookupByLibrary.simpleMessage("Envoyer le code"),
        "sub_upload_atKeys": MessageLookupByLibrary.simpleMessage(
            "Téléchargez votre fichier atKey. Ce fichier a été généré lorsque vous avez activé et couplé votre atSign et que vous avez été invité à le stocker dans un emplacement sécurisé."),
        "title_FAQ": MessageLookupByLibrary.simpleMessage("FAQ"),
        "title_activate_an_atSign":
            MessageLookupByLibrary.simpleMessage("Activer un atSign ?"),
        "title_important": MessageLookupByLibrary.simpleMessage("IMPORTANT!"),
        "title_intro": MessageLookupByLibrary.simpleMessage(
            "Cette application a été créée sur atPlatform. Toutes les applications atPlatform nécessitent un atSign. "),
        "title_pair_atSign_next":
            MessageLookupByLibrary.simpleMessage("Coupler avec cet appareil"),
        "title_pair_atSign_prev":
            MessageLookupByLibrary.simpleMessage("Vous avez sélectionné "),
        "title_save_your_key":
            MessageLookupByLibrary.simpleMessage("Enregistrer votre clé"),
        "title_select_atSign": MessageLookupByLibrary.simpleMessage(
            "Vous avez déjà des atsigns existants. Veuillez sélectionner un atSign ou continuer avec le nouveau."),
        "title_session_expired":
            MessageLookupByLibrary.simpleMessage("Votre session a expiré"),
        "title_setting_up_your_atSign": MessageLookupByLibrary.simpleMessage(
            "Configuration de votre atSign"),
        "title_shared_storage": MessageLookupByLibrary.simpleMessage(
            "Voulez-vous partager cet atsign intégré avec d\'autres applications sur atPlatform?"),
        "tutorial_activate_your_atSign": MessageLookupByLibrary.simpleMessage(
            "Appuyez ici pour activer votre atSign"),
        "tutorial_generate_atSign": MessageLookupByLibrary.simpleMessage(
            "Appuyez pour générer un nouvel atSign gratuit"),
        "tutorial_get_atSign": MessageLookupByLibrary.simpleMessage(
            "Si vous n\'avez pas d\'atSign, appuyez ici pour en obtenir un"),
        "tutorial_scan_QRCode": MessageLookupByLibrary.simpleMessage(
            "Appuyez pour scanner le code QR"),
        "tutorial_upload_atSign_key": MessageLookupByLibrary.simpleMessage(
            "Si vous avez un atSign, appuyez pour télécharger la clé atSign"),
        "tutorial_upload_image_QRCode": MessageLookupByLibrary.simpleMessage(
            "Appuyez pour télécharger le code QR de l\'image"),
        "tutorial_upload_your_atKey": MessageLookupByLibrary.simpleMessage(
            "Si vous avez un atSign activé, appuyez pour télécharger vos atKeys"),
        "upload_atKeys":
            MessageLookupByLibrary.simpleMessage("Télécharger atKeys"),
        "verification_code_has_been_sent_to":
            MessageLookupByLibrary.simpleMessage(
                "Un code de vérification a été envoyé à"),
        "verification_code_sent_to": MessageLookupByLibrary.simpleMessage(
            "Code de vérification envoyé à"),
        "verify_and_login":
            MessageLookupByLibrary.simpleMessage("Vérifier et se connecter"),
        "your_registered_email":
            MessageLookupByLibrary.simpleMessage("votre email enregistré.")
      };
}
