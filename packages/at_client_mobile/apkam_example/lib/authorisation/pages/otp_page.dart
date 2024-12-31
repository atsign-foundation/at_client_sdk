import 'package:apkam_example/authorisation/pages/authorisation_page_section.dart';
import 'package:apkam_example/authorisation/widgets/authorisation_section_header.dart';
import 'package:apkam_example/authorisation/widgets/tip_card.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

class OtpPage extends StatefulWidget {
  const OtpPage({required this.getOtp, super.key});

  final Future<Otp> getOtp;

  @override
  OtpPageState createState() => OtpPageState();
}

class OtpPageState extends State<OtpPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthorisationSectionHeader(
            title: AuthorisationPageSection.otp.title(context),
            icon: AuthorisationPageSection.otp.icon,
          ),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    'Use this to enroll other apps and devices.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<Otp>(
                    future: widget.getOtp,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      return Wrap(
                        alignment: WrapAlignment.center,
                        runAlignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...snapshot.data!.otp.split('').map(
                            (e) {
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Container(
                                  width: 50,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        e,
                                        style: Theme.of(context).textTheme.headlineMedium,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            tooltip: 'Refresh OTP',
                            icon: Icon(
                              Icons.refresh,
                              color: Theme.of(context).colorScheme.primary,
                              size: 32,
                            ),
                            onPressed: () {},
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy OTP'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const TipCard(
            tip: 'Setting up multiple devices? Set up a PIN to avoid regenerating new OTPs',
          ),
        ],
      ),
    );
  }
}
