import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

class AuthorisationHomePage extends StatefulWidget {
  const AuthorisationHomePage({super.key});

  @override
  AuthorisationHomePageState createState() => AuthorisationHomePageState();
}

class AuthorisationHomePageState extends State<AuthorisationHomePage> {
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);

  late Future<bool> isManagerKey;

  @override
  void initState() {
    super.initState();
    isManagerKey = service.isManagerKey();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.light,
          seedColor: Color(0xFFFF6633),
          primary: Color(0xFFFF6633),
          // surface: Color(0xFFF6F6F5),
          dynamicSchemeVariant: DynamicSchemeVariant.content,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(AtClientManager.getInstance().atClient.getCurrentAtSign()!),
        ),
        body: FutureBuilder<bool>(
          future: isManagerKey,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return Text('Error ${snapshot.error}');
            }
            final isManagerKey = snapshot.data as bool;
            if (!isManagerKey) {
              return Text('Your key is not a manager key');
            } else {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.key,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Manager Device',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Text(
                        'The app on this device can be used as an authenticator for all future apps & devices.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      // TODO: If there is a SPP, show that here.
                      const SizedBox(height: 18),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: 0,
                        child: InkWell(
                          onTap: () {},
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.question_mark,
                                  size: 32,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Requests',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const Spacer(),
                                const Icon(Icons.arrow_forward_ios),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'OTP',
                                    style: Theme.of(context).textTheme.headlineSmall,
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
                              ),
                              Text(
                                'Use this OTP to enroll other apps and devices.',
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<Otp>(
                                future: service.generateOtp(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }
                                  if (snapshot.hasError) {
                                    return Text('Error: ${snapshot.error}');
                                  }
                                  // TODO: This needs to work with many characters so maybe using Wrap or scaling the
                                  // text down if needed will be needed.
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: snapshot.data!.otp.split('').map(
                                      (e) {
                                        return Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Text(
                                                e,
                                                style: Theme.of(context).textTheme.headlineMedium,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ).toList(),
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
                      const SizedBox(height: 16),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: 0,
                        child: InkWell(
                          onTap: () {},
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.list,
                                  size: 32,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'All Enrollments',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const Spacer(),
                                const Icon(Icons.arrow_forward_ios),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
