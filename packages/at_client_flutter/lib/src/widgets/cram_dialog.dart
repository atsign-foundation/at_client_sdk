import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';
import 'package:flutter/material.dart';

/// A dialog that activates an atSign with its CRAM key and hands back the
/// client the activation opened, which the app owns.
///
/// Use `CramDialog.show` to display the dialog and handle the activation.
///
/// Required Parameters:
/// - [atSign]: the atSign to activate.
/// - [cramKey]: the CRAM key, bare or in the registrar's
///   `<atSign>:activation_key:<secret>` form.
/// - [preference]: the client's preference; [rootDomain] is stamped on it
///   when given.
///
/// Optional Parameters:
/// - [keys]: where the activation writes the atSign's first keys (default:
///   the platform keychain).
/// - [storage]: the client's local storage.
/// - [title]: A title string for the dialog (default: "Onboarding Atsign via cram").
/// - [description]: A description shown while the activation is in progress,
///   until the first progress event arrives; thereafter the live progress
///   message is shown (default: "Authenticating, please wait...").
/// - [progressBuilder]: An optional builder function to customize the display
///   of progress events. When supplied it takes over rendering entirely.
/// - [onOnboardingComplete]: invoked with the client once the activation
///   completes.
///
/// Returns:
/// - The `AtClient` the activation opened, or null if the process fails or is
///   cancelled.
class CramDialog extends StatefulWidget {
  const CramDialog({
    super.key,
    required this.atSign,
    required this.cramKey,
    required this.preference,
    this.rootDomain,
    this.keys,
    this.storage,
    this.progressBuilder,
    this.onOnboardingComplete,
    this.title,
    this.description,
    this.flows = const AtsignFlows(),
  });

  final String atSign;
  final String cramKey;
  final AtClientPreference preference;
  final AtRootDomain? rootDomain;
  final WrittenAtKeysIo? keys;
  final AtClientStorage? storage;
  final Widget Function(ProgressEvent)? progressBuilder;
  final void Function(AtClient client)? onOnboardingComplete;
  final String? title;
  final String? description;

  /// Injection seam for tests; defaults to the real lifecycle verbs.
  final AtsignFlows flows;

  static Future<AtClient?> show(
    BuildContext context, {
    required String atSign,
    required String cramKey,
    required AtClientPreference preference,
    AtRootDomain? rootDomain,
    WrittenAtKeysIo? keys,
    AtClientStorage? storage,
    Widget Function(ProgressEvent)? progressBuilder,
    void Function(AtClient client)? onOnboardingComplete,
    String? title,
    String? description,
  }) async {
    return await showDialog<AtClient>(
      context: context,
      builder: (context) => CramDialog(
        atSign: atSign,
        cramKey: cramKey,
        preference: preference,
        rootDomain: rootDomain,
        keys: keys,
        storage: storage,
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
  final AtSignLogger _logger = AtSignLogger('CramDialog');
  final StreamController<ProgressEvent> _progress =
      StreamController<ProgressEvent>.broadcast();

  @override
  void initState() {
    super.initState();
    // Kick off the activation exactly once. Starting it here rather than in
    // build() means a widget rebuild — e.g. the parent repainting during the
    // up-to-5-min provisioning wait — can't spawn a second activation.
    _onboard();
  }

  Future<void> _onboard() async {
    final secret = _parseCramKey(widget.cramKey);
    try {
      final client = await widget.flows.activate(
        widget.atSign,
        cramSecret: secret,
        keys: widget.keys ?? KeychainAtKeysIo(),
        preference: under(widget.preference, widget.rootDomain),
        storage: widget.storage,
        onProgress: _progress.add,
      );
      if (widget.onOnboardingComplete != null) {
        widget.onOnboardingComplete!(client);
      } else {
        _logger.info('Activated ${widget.atSign} as ${client.enrollmentId}');
      }
      if (mounted) Navigator.of(context).pop(client);
    } catch (e) {
      // Activation failed or timed out. Without an error path the dialog would
      // stay on screen forever and CramDialog.show() would never complete
      // (issue #1905 / #1909).
      _logger.severe('Onboarding via CRAM failed: $e');
      if (!mounted) return;
      // A timeout during activation usually means the newly-registered atSign
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
  void dispose() {
    _progress.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Onboarding"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<ProgressEvent>(
            stream: _progress.stream,
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
