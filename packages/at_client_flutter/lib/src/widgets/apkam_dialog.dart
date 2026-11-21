import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_client_flutter/src/widgets/shared/failure_message.dart';
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
///   submitted earlier is waited on again rather than repeated. This app and
///   device's own comes first, else this app's under any device name, else
///   the store's one request whatever app name it was filed under, which
///   the dialog adopts. One filed under another app or device name is shown
///   with the names it records, whatever namespaces it was filed for. The
///   passcode is asked for only when the store holds no request; a store
///   holding several the dialog cannot choose between is reported and
///   nothing is waited on or sent. Cancel abandons the request the dialog
///   waits on.
/// - [storage]: the client's local storage; with none, a Hive store under the
///   preference's `hiveStoragePath`, or the app's support directory.
/// - [signingAlgo], [keyExchangeMode]: the request's key algorithm and how
///   its symmetric key travels; with neither, the preference's posture
///   decides.
///
/// Returns:
/// - The `AtClient` opened on the approved keys, or null if the process fails
///   or is cancelled. Leaving the dialog before then stops the enrollment's
///   wait (`PendingEnrollment.stop`) and keeps the request, which the next
///   show resumes, and stops a client the approval opens after leaving. Only
///   its Cancel button, once the user confirms, abandons the request
///   (`PendingEnrollment.cancel`).
class ApkamActivationDialog extends StatefulWidget {
  final String atSign;
  final AtRootDomain rootDomain;

  /// The app name the atSign's manager sees the request under and approves
  /// it as. Keep it constant from one run of the app to the next: a request
  /// filed under an earlier name is still adopted, and shown with the names
  /// it records.
  final String appName;
  final String deviceName;
  final Map<String, String> namespaces;
  final AtClientPreference preference;
  final WrittenAtKeysIo? keys;
  final AtClientStorage? storage;

  /// Builds every connection the enrollment and the client open; see
  /// `Atsign.enroll`.
  final AtLookUpFactory? lookUps;
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
    this.lookUps,
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
    AtLookUpFactory? lookUps,
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
        lookUps: lookUps,
        signingAlgo: signingAlgo,
        keyExchangeMode: keyExchangeMode,
        themeData: Theme.of(context),
      ),
    );
  }
}

class _ApkamActivationDialogState extends State<ApkamActivationDialog> {
  final AtSignLogger _logger = AtSignLogger('ApkamActivationDialog');
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  final ScrollController _pinScrollController = ScrollController();
  bool _isLoading = false;
  String _status = 'Waiting for approval..';
  late final WrittenAtKeysIo _keys;
  StreamSubscription<dynamic>? _progress;
  PendingEnrollment? _waitingOn;

  /// The enrollment a confirmed Cancel could not abandon, which Cancel
  /// tries again.
  PendingEnrollment? _abandoning;

  /// The Cancel confirmation while it is showing.
  BuildContext? _confirming;

  /// Why the dialog can neither wait on a request in the key store nor send
  /// one, shown in place of the Activate button; null when it can.
  String? _blocked;

  @override
  void initState() {
    super.initState();
    _keys = widget.keys ?? KeychainAtKeysIo();
    _resumeIfPending();
  }

  /// A request already in the key store is waited on again rather than asking
  /// for a passcode it has already spent: this app and device's own, else
  /// this app's under any device name, else the one request the store holds
  /// under another app name, since `enroll` refuses a store that already
  /// holds one. Adopting one filed under another app or device name is logged
  /// as a warning.
  ///
  /// Several requests it cannot choose between block the dialog: `enroll`
  /// would refuse a new request while they are in the store.
  Future<void> _resumeIfPending() async {
    final PendingEnrollment? pending;
    try {
      pending =
          await _resume(app: widget.appName, device: widget.deviceName) ??
          await _resume(app: widget.appName) ??
          await _resume();
    } catch (e) {
      if (e is AtEnrollmentPendingException && e.severalMatched) {
        if (mounted) {
          setState(
            () => _blocked =
                'This device already has several requests to enroll '
                "${widget.atSign} waiting for approval, and this screen can't "
                'tell which one to wait for, or send another while they '
                'wait. Have them approved or denied, then try again.',
          );
        }
        return;
      }
      // An unreadable store is reported when the request goes out.
      return;
    }
    if (pending == null || !mounted) return;
    final adopted =
        pending.app != widget.appName || pending.device != widget.deviceName;
    if (adopted) {
      String quoted(String text) => '"${clipForMessage(text, quote: '"')}"';
      final byApp = pending.app.isEmpty ? '' : ' by app ${quoted(pending.app)}';
      final onDevice = pending.device.isEmpty
          ? ''
          : ' on device ${quoted(pending.device)}';
      final filedBy = '$byApp$onDevice';
      _logger.warning(
        'Adopting enrollment ${quoted(pending.enrollmentId)} of '
        '${widget.atSign}${filedBy.isEmpty ? '' : ', filed$filedBy,'} for app '
        '${widget.appName} on device ${widget.deviceName}',
      );
    }
    final filedApp = clipForMessage(pending.app);
    final filedDevice = clipForMessage(pending.device);
    final recorded =
        '${filedApp.isEmpty ? '' : ' as $filedApp'}'
        '${filedDevice.isEmpty ? '' : ' on $filedDevice'}';
    final filedAs = adopted && recorded.isNotEmpty ? ', filed$recorded' : '';
    final id = clipForMessage(pending.enrollmentId);
    setState(() {
      _isLoading = true;
      _status = 'Resuming enrollment $id$filedAs..';
    });
    await _awaitAndOpen(pending);
  }

  Future<PendingEnrollment?> _resume({String? app, String? device}) =>
      widget.flows.resumeEnrollment(
        widget.atSign,
        app: app,
        device: device,
        keys: _keys,
        preference: under(widget.preference, widget.rootDomain),
        lookUps: widget.lookUps,
      );

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
    lookUps: widget.lookUps,
  );

  Future<void> _awaitAndOpen(PendingEnrollment pending) async {
    if (!mounted) {
      await _stop(pending);
      return;
    }
    setState(() => _waitingOn = pending);
    _progress = pending.progress.listen((event) {
      if (mounted) setState(() => _status = event.msg);
    });
    try {
      final preference = under(widget.preference, widget.rootDomain);
      final client = await pending.client(
        preference,
        storage: await storageOrDefault(
          widget.atSign,
          preference,
          widget.storage,
        ),
      );
      if (!mounted) {
        // NOTE: nothing receives a client opened after the dismissal, and
        // while it is live the atSign cannot be opened again.
        await client.stop();
        return;
      }
      final confirming = _confirming;
      if (confirming != null && confirming.mounted) {
        Navigator.of(confirming).pop(false);
      }
      Navigator.of(context).pop(client);
    } catch (e) {
      // The approval was refused, the atServer went away, or the request was
      // wrong. Surface it instead of leaking an unhandled exception, and keep
      // the dialog open so the user can retry (issue #1909).
      if (!mounted || e is AtEnrollmentCancelledException) return;
      final message = _failureMessage(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      _waitingOn = null;
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

  /// What the dialog shows for [error], which ended the request or its wait.
  String _failureMessage(Object error) => failureMessage(
    widget.atSign,
    error,
    timedOut:
        'Activation timed out — the atServer could not be reached. '
        'Please check your connection and try again.',
  );

  /// Stops [pending]'s wait and keeps the request. A failure is logged,
  /// since the dialog is gone and there is nobody to tell.
  Future<void> _stop(PendingEnrollment pending) async {
    try {
      await pending.stop();
    } catch (e) {
      _logger.warning(
        'Could not stop the wait for enrollment ${pending.enrollmentId} of '
        '${widget.atSign}: $e',
      );
    }
  }

  /// Asks the user to confirm abandoning the request, then cancels it.
  Future<void> _onCancel() async {
    final retrying = _abandoning;
    final pending = retrying ?? _waitingOn;
    if (pending == null) return;
    if (retrying == null && !await _confirmAbandon(pending.enrollmentId)) {
      return;
    }
    try {
      await pending.cancel();
    } catch (e) {
      _logger.warning(
        'Could not remove the pending keys of enrollment '
        '${pending.enrollmentId} of ${widget.atSign}: $e',
      );
      if (!mounted) return;
      setState(() => _abandoning = pending);
      return;
    }
    if (!mounted) return;
    if (pending.approved) {
      await _openApproved(pending);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Enrollment ${pending.enrollmentId} abandoned. Ask the manager of '
          '${widget.atSign} to deny it.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  /// Hands back a client on the keys whose approval was written before the
  /// Cancel took effect, which lets the approval stand.
  Future<void> _openApproved(PendingEnrollment pending) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'The approval of enrollment ${pending.enrollmentId} landed before '
          'the Cancel took effect, so it stands.',
        ),
      ),
    );
    final AtClient client;
    try {
      client = await widget.flows.open(
        widget.atSign,
        keys: _keys,
        preference: under(widget.preference, widget.rootDomain),
        storage: widget.storage,
        lookUps: widget.lookUps,
      );
    } catch (e) {
      _logger.warning(
        'Could not open ${widget.atSign} on the approved keys of enrollment '
        '${pending.enrollmentId}: $e',
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) {
      // NOTE: nothing receives a client opened after the dismissal, and
      // while it is live the atSign cannot be opened again.
      await client.stop();
      return;
    }
    Navigator.of(context).pop(client);
  }

  /// Whether the user confirms abandoning enrollment [enrollmentId].
  Future<bool> _confirmAbandon(String enrollmentId) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) {
          _confirming = context;
          return AlertDialog(
            title: const Text('Abandon this request?'),
            content: Text(
              'This abandons enrollment $enrollmentId of ${widget.atSign}. '
              'Trying again needs a new OTP from another enrollment of '
              '${widget.atSign}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep waiting'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Abandon'),
              ),
            ],
          );
        },
      ).whenComplete(() => _confirming = null) ??
      false;

  @override
  void dispose() {
    final waitingOn = _waitingOn;
    if (waitingOn != null) unawaited(_stop(waitingOn));
    _progress?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _pinScrollController.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    final otp = _otpController.text;
    if (otp.length != 6 || _isLoading || _blocked != null) return;

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
      final message = _failureMessage(e);
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
            Row(
              children: [
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: const Icon(Icons.arrow_back, size: 20),
                ),
                const Spacer(),
                if (_waitingOn != null || _abandoning != null)
                  TextButton(onPressed: _onCancel, child: const Text('Cancel')),
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

            _abandoning != null
                ? Text(
                    'Could not abandon enrollment '
                    '${_abandoning!.enrollmentId}: its keys are still in the '
                    'key store. Choose Cancel to try again.',
                  )
                : _blocked != null
                ? Text(_blocked!)
                : _isLoading
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
