import 'package:apkam_example/authorisation/pages/authorisation_home_page.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';

import '../../authorisation/services/authorisation_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);

  late Future<void> serviceInit;

  @override
  void initState() {
    super.initState();
    serviceInit = service.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            FutureBuilder(
              future: serviceInit,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => AuthorisationHomePage(service: service),
                        ),
                      );
                    },
                    child: const Text('Authorisation Home Page'),
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
