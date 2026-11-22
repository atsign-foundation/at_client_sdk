import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';

/// {@template apkam_example_page}
/// An example page for the approving side of the APKAM enrollment flow.
///
/// This page has two parts:
/// 1. **Manager View**: Uses [EnrollmentRequestList] to see and manage incoming requests.
/// 2. **Passcode for Another Device**: A button that gets a one-time passcode
///    another device quotes to request enrollment, and says where to use it.
/// {@endtemplate}
class ApkamExamplePage extends StatefulWidget {
  const ApkamExamplePage({super.key, this.getPasscode});

  /// Gets the passcode the page shows; with none, the current client's
  /// `enrollments.otp()` does.
  final Future<Passcode> Function()? getPasscode;

  @override
  State<ApkamExamplePage> createState() => _ApkamExamplePageState();
}

class _ApkamExamplePageState extends State<ApkamExamplePage> {
  final AtSignLogger _logger = AtSignLogger('ApkamExample');
  Passcode? _passcode;

  @override
  Widget build(BuildContext context) {
    final atClient = AtClientManager.getInstance().atClient;
    final currentAtSign = atClient.getCurrentAtSign();
    final preferences = atClient.getPreferences();
    final root = preferences == null
        ? ''
        : ' -r ${preferences.rootDomain}:${preferences.rootPort}';
    final passcode = _passcode;

    return Scaffold(
      appBar: AppBar(title: Text('APKAM Demo ($currentAtSign)')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AuthorisationSectionHeader(
                      title: 'Manager View',
                      icon: Icons.admin_panel_settings_outlined,
                    ),
                    const TipCard(
                      tip:
                          'EnrollmentRequestList listens for real-time notifications.',
                    ),
                    const SizedBox(height: 16),
                    const EnrollmentRequestList(useShrinkWrap: true),

                    const Divider(height: 48),

                    const AuthorisationSectionHeader(
                      title: 'Passcode for Another Device',
                      icon: Icons.phonelink_setup_outlined,
                    ),
                    const Text(
                      'Get a one-time passcode that another device quotes to '
                      'request enrollment. Its request then appears in the '
                      'manager view above.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _getPasscode,
                      icon: const Icon(Icons.password),
                      label: const Text('Get Passcode'),
                    ),

                    if (passcode != null) ...[
                      const SizedBox(height: 24),
                      SelectableText(
                        'Passcode: ${passcode.value}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'On another device, enter it in this example\'s '
                        '"Register an atSign with APKAM", or run:',
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        'at_activate enroll -a $currentAtSign$root '
                        '--app <app> --device <device> --namespaces <ns:rw> '
                        '--passcode ${passcode.value} -k <keyfile>',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'While it waits, at_activate cancel -a $currentAtSign '
                        '-k <keyfile> gives that request up.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gets a one-time passcode from the manager's client, which is enrolled
  /// and may issue one, and shows it.
  Future<void> _getPasscode() async {
    final getPasscode =
        widget.getPasscode ??
        () => AtClientManager.getInstance().atClient.enrollments.otp();
    try {
      final passcode = await getPasscode();
      if (mounted) setState(() => _passcode = passcode);
    } catch (e) {
      _logger.severe('Could not get a passcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not get a passcode: $e')));
      }
    }
  }
}
