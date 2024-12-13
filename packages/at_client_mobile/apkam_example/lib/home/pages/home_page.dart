import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Page'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final pending = await AuthorisationService().getAllEnrollmentRequests(
              AtClientManager.getInstance().atClient,
            );
            print(pending);
          },
          child: Text('Get Pending Requests'),
        ),
      ),
    );
  }
}
