import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';

/// A dialog widget that facilitates authentication using PKAM.
///
/// Use `PkamDialog.show` to display the dialog and handle the authentication process.
///
/// Required Parameters:
/// - [request]: An `AtAuthRequest` containing details for the authentication process.
///
/// Optional Parameters:
/// - [title]: A title string for the dialog (default: "Authenticating via pkam").
/// - [description]: A description string displayed while authentication is in progress (default: "Validating your atKeys...").
/// - [progressBuilder]: An optional builder function to customize the display of progress events.
///   It takes a `ProgressEvent` and returns a `Widget`, allowing for tailored UI updates during the authentication process.
///   Otherwise, by default it will pop the dialog with the progress event.
/// - [onAuthenticationComplete]: An optional callback function that is invoked when the authentication process completes successfully.
///
/// Returns:
/// - An `AtAuthResponse` upon successful authentication, or null if the process fails or is cancelled.
class PkamDialog extends StatelessWidget {
  PkamDialog({
    super.key,
    required this.request,
    this.progressBuilder,
    this.onAuthenticationComplete,
    this.title,
    this.description,
    this.backupKeys,
  });
  final AuthService auth = AuthService();
  final AtAuthRequest request;
  final Widget Function(ProgressEvent)? progressBuilder;
  final void Function(AtAuthRequest)? onAuthenticationComplete;
  final String? title;
  final String? description;
  final List<WrittenAtKeysIo>? backupKeys;
  final AtSignLogger _logger = AtSignLogger('PkamDialog');

  static Future<AtAuthResponse?> show(
    BuildContext context, {
    required AtAuthRequest request,
    Widget Function(ProgressEvent)? progressBuilder,
    dynamic Function(AtAuthRequest)? onAuthenticationComplete,
    String? title,
    String? description,
    List<WrittenAtKeysIo>? backupKeys,
  }) async {
    return showDialog<AtAuthResponse>(
      context: context,
      builder: (context) => PkamDialog(
        request: request,
        progressBuilder: progressBuilder,
        onAuthenticationComplete: onAuthenticationComplete,
        title: title,
        description: description,
        backupKeys: backupKeys,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    auth
        .authenticate(request, backupKeys: backupKeys)
        .then((response) {
          if (onAuthenticationComplete != null) {
            onAuthenticationComplete!(request);
          } else {
            _logger.info(response.toString());
          }
          if (context.mounted) Navigator.of(context).pop(response);
        })
        .catchError((Object e) {
          // Authentication failed (e.g. invalid atKeys or the atServer is
          // unreachable). Without an error path the dialog would hang forever and
          // PkamDialog.show() would never complete (issue #1909).
          _logger.severe('Authentication via PKAM failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Authentication failed. Please check your atKeys and connection, '
                  'then try again.',
                ),
              ),
            );
            Navigator.of(context).pop(null);
          }
        });
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder(
          stream: auth.progressStream,
          builder: (context, snapshot) {
            // When a custom progressBuilder is provided, render it for each
            // progress event. Otherwise keep showing the loading indicator
            // until authentication completes and the dialog is popped —
            // returning an empty widget here caused a blank dialog box to
            // flash on screen during login (issue #1956).
            if (snapshot.hasData && progressBuilder != null) {
              return progressBuilder!(snapshot.data as ProgressEvent);
            }
            return LoadingDialog(
              title: title ?? "Authenticating via pkam",
              description: description ?? "Validating your atKeys...",
              themeData: Theme.of(context),
            );
          },
        ),
      ),
    );
  }
}
