import 'package:flutter/material.dart';

import '../providers/otp_provider.dart';
import '../providers/selected_section_provider.dart';
import '../widgets/authorisation_section_header.dart';
import '../widgets/tip_card.dart';
import 'authorisation_page_section.dart';

class OtpPage extends StatefulWidget {
  const OtpPage({super.key});

  @override
  OtpPageState createState() => OtpPageState();
}

class OtpPageState extends State<OtpPage> {
  @override
  Widget build(BuildContext context) {
    final activeOtp = ActiveOtpProvider.of(context);
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
                  // TODO: Create a nicer looking loading state
                  if (activeOtp.isFetching)
                    const Center(
                      child: CircularProgressIndicator(),
                    ),
                  if (activeOtp.error != null) Text('Error: ${activeOtp.error!}'),
                  if (activeOtp.otp != null)
                    Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...activeOtp.otp!.otp.split('').map(
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
                          onPressed: () async {
                            await activeOtp.generateOtp(refresh: true);
                          },
                        ),
                      ],
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
          TipCard(
            tip: 'Setting up multiple devices? Set up a PIN to avoid regenerating new OTPs',
            onTap: () {
              SelectedSectionProvider.of(context).updateSelectedSection(AuthorisationPageSection.setPin);
            },
          ),
        ],
      ),
    );
  }
}
