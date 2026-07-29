import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:at_commons/at_commons.dart' show AtTimeoutException;
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';

/// A dialog widget that facilitates onboarding an Atsign using a CRAM key.
///
/// Use `CramDialog.show` to display the dialog and handle the onboarding process.
///
/// Required Parameters:
/// - [request]: An `AtOnboardingRequest` containing details for the onboarding process.
/// - [cramKey]: The CRAM key used for authentication during onboarding.
///
/// Optional Parameters:
/// - [title]: A title string for the dialog (default: "Onboarding Atsign via cram").
/// - [description]: A description shown while onboarding is in progress, until the
///   first progress event arrives; thereafter the live progress message is shown
///   (default: "Authenticating, please wait...").
/// - [progressBuilder]: An optional builder function to customize the display of progress events.
///   It takes a `ProgressEvent` and returns a `Widget`, allowing for tailored UI updates during the onboarding process.
///   When supplied it takes over rendering entirely.
/// - [onOnboardingComplete]: An optional callback function that is invoked when the onboarding process completes successfully.
///
/// Returns:
/// - An `AtOnboardingResponse` upon successful onboarding, or null if the process fails or is cancelled.
class CramDialog extends StatefulWidget {
  const CramDialog({
    super.key,
    required this.request,
    required this.cramKey,
    this.progressBuilder,
    this.onOnboardingComplete,
    this.title,
    this.description,
    this.authService,
  });

  final AtOnboardingRequest request;
  final String cramKey;
  final Widget Function(ProgressEvent)? progressBuilder;
  final void Function(AtOnboardingRequest)? onOnboardingComplete;
  final String? title;
  final String? description;

  /// Injection seam for tests; defaults to a real [AuthService].
  final AuthService? authService;

  static Future<AtOnboardingResponse?> show(
    BuildContext context, {
    required AtOnboardingRequest request,
    required String cramKey,
    Widget Function(ProgressEvent)? progressBuilder,
    void Function(AtOnboardingRequest)? onOnboardingComplete,
    String? title,
    String? description,
  }) async {
    return await showDialog<AtOnboardingResponse>(
      context: context,
      builder: (context) => CramDialog(
        request: request,
        cramKey: cramKey,
        progressBuilder: progressBuilder,
        onOnboardingComplete: onOnboardingComplete,
        title: title,
        description: description,
      ),
    );
  }

  @override
  State<CramDialog> createState() => _CramDialogState();
}

class _CramDialogState extends State<CramDialog> {
  late final AuthService _authService;
  final AtSignLogger _logger = AtSignLogger('CramDialog');

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    // Kick off onboarding exactly once. Starting it here rather than in build()
    // means a widget rebuild — e.g. the parent repainting during the up-to-5-min
    // provisioning wait — can't spawn a second onboard() call.
    _onboard();
  }

  Future<void> _onboard() async {
    final secret = _parseCramKey(widget.cramKey);
    try {
      final response = await _authService.onboard(widget.request, secret);
      if (widget.onOnboardingComplete != null) {
        widget.onOnboardingComplete!(widget.request);
      } else {
        _logger.info('Onboarding response: $response');
      }
      if (mounted) Navigator.of(context).pop(response);
    } catch (e) {
      // Onboarding failed or timed out. Without an error path the dialog would
      // stay on screen forever and CramDialog.show() would never complete
      // (issue #1905 / #1909).
      _logger.severe('Onboarding via CRAM failed: $e');
      if (!mounted) return;
      // A timeout during onboarding usually means the newly-registered atSign
      // is still provisioning, not a hard failure — say so and invite a retry.
      final message = e is AtTimeoutException
          ? 'Onboarding is taking longer than expected — your atSign may still '
                'be provisioning. Please try again in a moment.'
          : 'Onboarding failed. Please check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Onboarding"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<ProgressEvent>(
            stream: _authService.progressStream,
            builder: (context, snapshot) {
              // A custom progressBuilder takes over rendering entirely.
              if (snapshot.hasData && widget.progressBuilder != null) {
                return widget.progressBuilder!(snapshot.data!);
              }
              // Otherwise show the loading indicator, surfacing the latest
              // progress message so a multi-minute provisioning wait shows live
              // status rather than static text. (Returning an empty widget here
              // caused a blank dialog box to flash on screen — issue #1956.)
              return LoadingDialog(
                title: widget.title ?? "Onboarding Atsign via cram",
                description: snapshot.hasData
                    ? snapshot.data!.msg
                    : (widget.description ?? "Authenticating, please wait..."),
              );
            },
          ),
        ],
      ),
    );
  }

  String _parseCramKey(String input) {
    final trimmedInput = input.trim();
    final match = ActivateRegex.cram.firstMatch(trimmedInput);
    if (match != null) {
      return match.namedGroup(ActivateRegexGroups.activationKey)!;
    }
    return trimmedInput; // fallback: assume input is the secret
  }
}

class ActivateRegex {
  // CRAM authentication: <atsign>:cram:<secret>
  static final cram = RegExp(
    r'^(?<atsign>[^:]+):activation_key:(?<secret>.+)$',
  );

  // Enrollment: <atsign>:enroll:otp:<otp>[:name:<device>]
  static final enroll = RegExp(
    r'^(?<atsign>[^:]+):enroll:otp:(?<otp>[A-Za-z0-9]{6})'
    r'(?::name:(?<device_name>[^]+))?$', // ?: indicates a non-capturing group
  );
}

/// Named capture groups used in [ActivateRegex]
class ActivateRegexGroups {
  static const atsign = 'atsign';
  static const activationKey = 'secret';
  static const otp = 'otp';
  static const deviceName = 'device_name';
  static const keyfilePath = 'keyfile_path';
}
