import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
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
/// - [description]: A description string displayed while onboarding is in progress (default: "Authenticating, please wait...").
/// - [progressBuilder]: An optional builder function to customize the display of progress events.
///   It takes a `ProgressEvent` and returns a `Widget`, allowing for tailored UI updates during the onboarding process.
///   Otherwise, by default it will pop the dialog with the progress event.
/// - [onOnboardingComplete]: An optional callback function that is invoked when the onboarding process completes successfully.
///
/// Returns:
/// - An `AtOnboardingResponse` upon successful onboarding, or null if the process fails or is cancelled.
class CramDialog extends StatelessWidget {
  CramDialog({
    super.key,
    required this.request,
    required this.cramKey,
    this.progressBuilder,
    this.onOnboardingComplete,
    this.title,
    this.description,
    this.operationTimeout = const Duration(seconds: 75),
    AuthService? authService,
  }) : _authService = authService ?? AuthService();

  final AtOnboardingRequest request;
  final String cramKey;
  final AuthService _authService;
  final Widget Function(ProgressEvent)? progressBuilder;
  final void Function(AtOnboardingRequest)? onOnboardingComplete;
  final String? title;
  final String? description;
  final Duration operationTimeout;
  final AtSignLogger _logger = AtSignLogger('CramDialog');

  static Future<AtOnboardingResponse?> show(
    BuildContext context, {
    required AtOnboardingRequest request,
    required String cramKey,
    Widget Function(ProgressEvent)? progressBuilder,
    void Function(AtOnboardingRequest)? onOnboardingComplete,
    String? title,
    String? description,
    Duration operationTimeout = const Duration(seconds: 75),
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
        operationTimeout: operationTimeout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String secret = _parseCramKey(cramKey);
    Future<void>(() async {
      try {
        final response = await _authService.onboard(request, secret).timeout(
          operationTimeout,
          onTimeout: () => throw TimeoutException(
            'Onboarding timed out. Please check your network and try again.',
          ),
        );
        if (onOnboardingComplete != null) {
          onOnboardingComplete!(request);
        } else {
          _logger.info('Onboarding response: $response');
        }
        if (context.mounted) {
          Navigator.of(context).pop(response);
        }
      } catch (e, st) {
        _logger.warning('Onboarding failed', e, st);
        if (!context.mounted) return;
        _showError(context, e.toString());
        Navigator.of(context).pop();
      }
    });
    return AlertDialog(
      title: Text("Onboarding"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder(
            stream: _authService.progressStream,
            builder: (context, snapshot) {
              if (progressBuilder == null) {
                return LoadingDialog(
                  title: title ?? "Onboarding Atsign via cram",
                  description: description ?? "Authenticating, please wait...",
                );
              }
              if (!snapshot.hasData) {
                return LoadingDialog(
                  title: title ?? "Onboarding Atsign via cram",
                  description: description ?? "Authenticating, please wait...",
                );
              }
              final progress = snapshot.data as ProgressEvent;
              return progressBuilder!(progress);
            },
          ),
        ],
      ),
    );
  }

  void _showError(BuildContext context, String error) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error.isNotEmpty ? error : 'Onboarding failed. Please try again.',
        ),
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
