import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_chops/at_chops.dart';
import 'package:flutter/material.dart';

/// {@template apkam_example_page}
/// An example page demonstrating the APKAM enrollment flow.
///
/// This page has two parts:
/// 1. **Manager View**: Uses [EnrollmentRequestList] to see and manage incoming requests.
/// 2. **Requester Simulator**: A button that simulates a "New Device" requesting access.
/// {@endtemplate}
class ApkamExamplePage extends StatefulWidget {
  const ApkamExamplePage({super.key});

  @override
  State<ApkamExamplePage> createState() => _ApkamExamplePageState();
}

class _ApkamExamplePageState extends State<ApkamExamplePage> {
  final AtSignLogger _logger = AtSignLogger('ApkamExample');
  final List<RequesterStatus> _simulatedRequests = [];

  @override
  Widget build(BuildContext context) {
    final currentAtSign =
        AtClientManager.getInstance().atClient.getCurrentAtSign();

    return Scaffold(
      appBar: AppBar(
        title: Text('APKAM Demo ($currentAtSign)'),
      ),
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
                          'This section uses the EnrollmentRequestList widget to listen for real-time notifications.',
                    ),
                    const SizedBox(height: 16),
                    // THE BIG WIDGET: Displays and manages incoming requests
                    const EnrollmentRequestList(useShrinkWrap: true),

                    const Divider(height: 48),

                    const AuthorisationSectionHeader(
                      title: 'Requester Simulator',
                      icon: Icons.phonelink_setup_outlined,
                    ),
                    const Text(
                      'Click the button below to simulate a new app/device requesting an enrollment.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _simulateNewRequest,
                      icon: const Icon(Icons.add_to_home_screen),
                      label: const Text('Simulate New Enrollment Request'),
                    ),

                    if (_simulatedRequests.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'My Active Requests (Simulated)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final req in _simulatedRequests)
                        Card(
                          child: ListTile(
                            leading: _getStatusIcon(req.status),
                            title: Text('${req.appName} | ${req.deviceName}'),
                            subtitle: Text('Status: ${req.status.name}'),
                            trailing: req.status == EnrollmentStatus.pending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : null,
                          ),
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

  /// Simulates the "Requester" side of the APKAM flow.
  ///
  /// This method:
  /// 1. Uses [AtEnrollment.create()] to submit a new request.
  /// 2. Starts a polling mechanism via [waitForApproval] to get status updates.
  Future<void> _simulateNewRequest() async {
    final atClient = AtClientManager.getInstance().atClient;
    final currentAtSign = atClient.getCurrentAtSign()!;

    // Create unique app/device names for simulation
    final timestamp = DateTime.now().millisecondsSinceEpoch % 1000;
    final appName = 'SimulatedApp_$timestamp';
    final deviceName = 'Device_$timestamp';

    final requesterStatus = RequesterStatus(
      appName: appName,
      deviceName: deviceName,
      status: EnrollmentStatus.pending,
    );

    setState(() {
      _simulatedRequests.insert(0, requesterStatus);
    });

    try {
      _logger.info('STEP 1: Initiating enrollment request for $appName');

      final atLookup = AtLookupImpl(
        currentAtSign,
        atClient.getPreferences()!.rootDomain,
        atClient.getPreferences()!.rootPort,
      );

      // STEP 1: Generate an OTP using the MANAGER client
      final otpResponse = await atClient.getRemoteSecondary()!.atLookUp.executeCommand(
            'otp:get\n',
            auth: true,
          );
      final cleanOtp = otpResponse?.replaceFirst('data:', '').trim();

      // STEP 2: Submit the enrollment request (The "Requester" side)
      final enrollment = AtEnrollment.create();
      
      // We generate a key pair for the simulation
      final apkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();

      final request = AtEnrollmentRequest(
        atSign: currentAtSign,
        appName: appName,
        deviceName: deviceName,
        namespaces: {'public': 'rw'}, 
        otp: cleanOtp!,
        apkamPublicKey: apkamKeyPair.atPublicKey.publicKey,
      );

      final response = await enrollment.submit(request, atLookup);
      _logger.info('STEP 2: Request submitted. ID: ${response.enrollmentId}');

      // STEP 3: Wait for approval (polling the status)
      _logger.info('STEP 3: Polling for status updates...');
      
      await enrollment.waitForApproval(
        response,
        retryInterval: const Duration(seconds: 5),
        maxRetries: 12, 
      );

      _logger.info('STEP 4: Enrollment APPROVED!');
      if (mounted) {
        setState(() {
          requesterStatus.status = EnrollmentStatus.approved;
        });
      }

    } catch (e) {
      _logger.severe('Simulation failed: $e');
      if (mounted) {
        setState(() {
          requesterStatus.status = EnrollmentStatus.denied;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Simulation error: $e')),
        );
      }
    }
  }

  Widget _getStatusIcon(EnrollmentStatus status) {
    switch (status) {
      case EnrollmentStatus.approved:
        return const Icon(Icons.check_circle, color: Colors.green);
      case EnrollmentStatus.denied:
      case EnrollmentStatus.revoked:
      case EnrollmentStatus.expired:
        return const Icon(Icons.error, color: Colors.red);
      default:
        return const Icon(Icons.hourglass_empty, color: Colors.orange);
    }
  }
}

class RequesterStatus {
  final String appName;
  final String deviceName;
  EnrollmentStatus status;

  RequesterStatus({
    required this.appName,
    required this.deviceName,
    required this.status,
  });
}
