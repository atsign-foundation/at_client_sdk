import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_commons/at_commons.dart' show AtTimeoutException;
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
/// - [description]: A description shown while authentication is in progress, until
///   the first progress event arrives; thereafter the live progress message is
///   shown (default: "Validating your atKeys...").
/// - [progressBuilder]: An optional builder function to customize the display of progress events.
///   It takes a `ProgressEvent` and returns a `Widget`, allowing for tailored UI updates during the authentication process.
///   When supplied it takes over rendering entirely.
/// - [onAuthenticationComplete]: An optional callback function that is invoked when the authentication process completes successfully.
///
/// Returns:
/// - An `AtAuthResponse` upon successful authentication, or null if the process fails or is cancelled.
class PkamDialog extends StatefulWidget {
  const PkamDialog({
    super.key,
    required this.request,
    this.progressBuilder,
    this.onAuthenticationComplete,
    this.title,
    this.description,
    this.backupKeys,
  });

  final AtAuthRequest request;
  final Widget Function(ProgressEvent)? progressBuilder;
  final void Function(AtAuthRequest)? onAuthenticationComplete;
  final String? title;
  final String? description;
  final List<WrittenAtKeysIo>? backupKeys;

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
  State<PkamDialog> createState() => _PkamDialogState();
}

class _PkamDialogState extends State<PkamDialog> {
  final AuthService _auth = AuthService();
  final AtSignLogger _logger = AtSignLogger('PkamDialog');

  @override
  void initState() {
    super.initState();
    // Kick off authentication exactly once. Starting it here rather than in
    // build() means a widget rebuild can't spawn a second authenticate() call.
    _authenticate();
  }

  Future<void> _authenticate() async {
    try {
      final response = await _auth.authenticate(
        widget.request,
        backupKeys: widget.backupKeys,
      );
      if (widget.onAuthenticationComplete != null) {
        widget.onAuthenticationComplete!(widget.request);
      } else {
        _logger.info(response.toString());
      }
      if (mounted) Navigator.of(context).pop(response);
    } catch (e) {
      // Authentication failed or timed out. Without an error path the dialog
      // would hang forever and PkamDialog.show() would never complete
      // (issue #1909).
      _logger.severe('Authentication via PKAM failed: $e');
      if (!mounted) return;
      final message = e is AtTimeoutException
          ? 'Authentication timed out — the atServer could not be reached. '
                'Please check your connection and try again.'
          : 'Authentication failed. Please check your atKeys and connection, '
                'then try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<ProgressEvent>(
          stream: _auth.progressStream,
          builder: (context, snapshot) {
            // A custom progressBuilder takes over rendering entirely.
            if (snapshot.hasData && widget.progressBuilder != null) {
              return widget.progressBuilder!(snapshot.data!);
            }
            // Otherwise show the loading indicator, surfacing the latest
            // progress message so the wait shows live status rather than static
            // text. (Returning an empty widget here caused a blank dialog box to
            // flash on screen during login — issue #1956.)
            return LoadingDialog(
              title: widget.title ?? "Authenticating via pkam",
              description: snapshot.hasData
                  ? snapshot.data!.msg
                  : (widget.description ?? "Validating your atKeys..."),
              themeData: Theme.of(context),
            );
          },
        ),
      ),
    );
  }
}
