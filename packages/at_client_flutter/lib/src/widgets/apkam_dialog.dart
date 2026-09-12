import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:flutter/services.dart';

/// A dialog that enrols this device with an atSign by quoting a one-time
/// passcode, waits for an enrolled client to approve, and hands back the
/// client that opens on the approved keys; the app owns it.
///
/// Use `ApkamActivationDialog.show` to display the dialog and handle the OTP
/// verification process.
///
/// Required Parameters:
/// - [atSign], [rootDomain], [appName], [deviceName], [namespaces]: what the
///   request asks for.
/// - [preference]: the client's preference; [rootDomain] is stamped on it.
///
/// Optional Parameters:
/// - [keys]: where this enrollment's keys are filed and read back from, the
///   platform keychain by default. It is also the resume record: a request
///   submitted earlier for the same app and device is waited on again rather
///   than repeated, so the passcode is only asked for when nothing is pending.
/// - [storage]: the client's local storage.
/// - [signingAlgo], [keyExchangeMode]: the request's key algorithm and how
///   its symmetric key travels; with neither, the preference's posture
///   decides.
///
/// Returns:
/// - The `AtClient` opened on the approved keys, or null if the process fails
///   or is cancelled.
class ApkamActivationDialog extends StatefulWidget {
  final String atSign;
  final AtRootDomain rootDomain;
  final String appName;
  final String deviceName;
  final Map<String, String> namespaces;
  final AtClientPreference preference;
  final WrittenAtKeysIo? keys;
  final AtClientStorage? storage;
  final SigningAlgoType? signingAlgo;
  final EnrollmentKeyExchangeMode? keyExchangeMode;

  final ThemeData themeData;

  /// Injection seam for tests; defaults to the real lifecycle verbs.
  final AtsignFlows flows;

  const ApkamActivationDialog({
    super.key,
    required this.atSign,
    required this.rootDomain,
    required this.appName,
    required this.deviceName,
    required this.namespaces,
    required this.preference,
    this.keys,
    this.storage,
    this.signingAlgo,
    this.keyExchangeMode,
    required this.themeData,
    this.flows = const AtsignFlows(),
  });

  @override
  State<ApkamActivationDialog> createState() => _ApkamActivationDialogState();

  /// Show the ApkamActivationDialog and return the client it opened.
  static Future<AtClient?> show(
    BuildContext context, {
    required String atSign,
    required AtRootDomain rootDomain,
    required String appName,
    required String deviceName,
    required Map<String, String> namespaces,
    required AtClientPreference preference,
    WrittenAtKeysIo? keys,
    AtClientStorage? storage,
    SigningAlgoType? signingAlgo,
    EnrollmentKeyExchangeMode? keyExchangeMode,
  }) async {
    return showDialog<AtClient>(
      context: context,
      builder: (context) => ApkamActivationDialog(
        atSign: atSign,
        rootDomain: rootDomain,
        appName: appName,
        deviceName: deviceName,
        namespaces: namespaces,
        preference: preference,
        keys: keys,
        storage: storage,
        signingAlgo: signingAlgo,
        keyExchangeMode: keyExchangeMode,
        themeData: Theme.of(context),
      ),
    );
  }
}

class _ApkamActivationDialogState extends State<ApkamActivationDialog> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  final ScrollController _pinScrollController = ScrollController();
  bool _isLoading = false;
  String _status = 'Waiting for approval..';
  late final WrittenAtKeysIo _keys;
  StreamSubscription<dynamic>? _progress;

  @override
  void initState() {
    super.initState();
    _keys = widget.keys ?? KeychainAtKeysIo();
    _resumeIfPending();
  }

  /// A request already in the key store for this app and device is waited on
  /// again rather than asking for a passcode it has already spent.
  Future<void> _resumeIfPending() async {
    final PendingEnrollment? pending;
    try {
      pending = await widget.flows.resumeEnrollment(
        widget.atSign,
        app: widget.appName,
        device: widget.deviceName,
        keys: _keys,
        preference: under(widget.preference, widget.rootDomain),
      );
    } catch (e) {
      // An unreadable store is reported when the request goes out.
      return;
    }
    if (pending == null || !mounted) return;
    setState(() {
      _isLoading = true;
      _status = 'Resuming enrollment ${pending!.enrollmentId}..';
    });
    await _awaitAndOpen(pending);
  }

  Future<PendingEnrollment> _sendEnrollment(String otp) => widget.flows.enroll(
    widget.atSign,
    otp: otp,
    app: widget.appName,
    device: widget.deviceName,
    namespaces: widget.namespaces,
    keys: _keys,
    preference: under(widget.preference, widget.rootDomain),
    signingAlgo: widget.signingAlgo,
    keyExchangeMode: widget.keyExchangeMode,
  );

  Future<void> _awaitAndOpen(PendingEnrollment pending) async {
    _progress = pending.progress.listen((event) {
      if (mounted) setState(() => _status = event.msg);
    });
    try {
      final client = await pending.client(
        under(widget.preference, widget.rootDomain),
        storage: widget.storage,
      );
      if (!mounted) return;
      Navigator.of(context).pop(client);
    } catch (e) {
      // The approval was refused, the atServer went away, or the request was
      // wrong. Surface it instead of leaking an unhandled exception, and keep
      // the dialog open so the user can retry (issue #1909).
      if (!mounted) return;
      final message = e is AtTimeoutException
          ? 'Activation timed out — the atServer could not be reached. '
                'Please check your connection and try again.'
          : 'Activation failed. Please check the code and your connection, '
                'then try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      await _progress?.cancel();
      _progress = null;
      // Guard against setState after the dialog was dismissed mid-await; a bare
      // `return` here would instead swallow any in-flight exception.
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _progress?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _pinScrollController.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    final otp = _otpController.text;
    if (otp.length != 6 || _isLoading) return;

    setState(() {
      _isLoading = true;
      _status = 'Waiting for approval..';
    });

    final PendingEnrollment pending;
    try {
      pending = await _sendEnrollment(otp);
    } catch (e) {
      // The request itself was refused (a wrong passcode, most often) or the
      // atServer could not be reached; keep the dialog open for a retry.
      if (!mounted) return;
      final message = e is AtTimeoutException
          ? 'Activation timed out — the atServer could not be reached. '
                'Please check your connection and try again.'
          : 'Activation failed. Please check the code and your connection, '
                'then try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() {
        _isLoading = false;
      });
      return;
    }
    await _awaitAndOpen(pending);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 24,
        24,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: Colors.white,
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button
            Row(
              children: [
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: const Icon(Icons.arrow_back, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Activate APKAM',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: widget.themeData.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            // Description
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text:
                        'A 6-digit verification code needs to be generated for ',
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: widget.atSign,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: '. Enter the code below to activate APKAM.',
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      height: 1.5,
                    ),
                  ),
                ],
                style: TextStyle(
                  fontSize: 14,
                  color: widget.themeData.colorScheme.secondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // OTP Input boxes
            LayoutBuilder(
              builder: (context, constraints) {
                const otpCount = 6;
                const itemGap = 12.0;
                final idealSize =
                    (constraints.maxWidth - ((otpCount - 1) * itemGap)) /
                    otpCount;
                final otpSize = idealSize.clamp(52.0, 56.0).toDouble();
                final viewportWidth = constraints.maxWidth;

                final defaultPinTheme = PinTheme(
                  width: otpSize,
                  height: otpSize,
                  textStyle: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: const Border.fromBorderSide(
                      BorderSide(color: Color(0xFFE0E0E0), width: 1),
                    ),
                  ),
                );

                return SingleChildScrollView(
                  controller: _pinScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Pinput(
                    controller: _otpController,
                    focusNode: _otpFocusNode,
                    autofocus: true,
                    length: otpCount,
                    closeKeyboardWhenCompleted: false,
                    separatorBuilder: (_) => const SizedBox(width: itemGap),
                    keyboardType: TextInputType.visiblePassword,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        newValue = newValue.copyWith(
                          text: newValue.text.toUpperCase(),
                        );
                        return newValue;
                      }),
                    ],
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: defaultPinTheme.copyWith(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.themeData.colorScheme.secondary,
                          width: 2,
                        ),
                      ),
                    ),
                    submittedPinTheme: defaultPinTheme,
                    onChanged: (value) {
                      final activeIndex = value.length >= otpCount
                          ? otpCount - 1
                          : value.length;

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted || !_pinScrollController.hasClients) {
                          return;
                        }

                        final pinStart = activeIndex * (otpSize + itemGap);
                        final pinEnd = pinStart + otpSize;
                        final currentOffset = _pinScrollController.offset;
                        final viewStart = currentOffset;
                        final viewEnd = currentOffset + viewportWidth;
                        const edgePadding = 8.0;

                        double? targetOffset;
                        if (pinStart < viewStart + edgePadding) {
                          targetOffset = pinStart - edgePadding;
                        } else if (pinEnd > viewEnd - edgePadding) {
                          targetOffset = pinEnd - viewportWidth + edgePadding;
                        }

                        if (targetOffset == null) return;

                        final clampedOffset = targetOffset.clamp(
                          _pinScrollController.position.minScrollExtent,
                          _pinScrollController.position.maxScrollExtent,
                        );

                        if ((clampedOffset - currentOffset).abs() < 1) {
                          return;
                        }

                        _pinScrollController.animateTo(
                          clampedOffset,
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                        );
                      });
                    },
                    onCompleted: (_) => _submitOtp(),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),

            // Submit button
            _isLoading
                ? Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        Text(_status),
                      ],
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _submitOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeData.colorScheme.secondary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Activate APKAM',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
