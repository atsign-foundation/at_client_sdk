import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../../authorisation/models/models.dart';
import '../../authorisation/services/authorisation_service.dart';

class OtpPage extends StatefulWidget {
  const OtpPage({super.key});
  @override
  OtpPageState createState() => OtpPageState();
}

class OtpPageState extends State<OtpPage> {
  late final service = AuthorisationService(AtClientManager.getInstance().atClient);
  late final sppController = TextEditingController();

  late Future<Otp> getOtp;

  @override
  void initState() {
    super.initState();
    getOtp = service.generateOtp();
  }

  @override
  void dispose() {
    sppController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Page'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FutureBuilder<Otp>(
            future: getOtp,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              return Text('OTP: ${snapshot.data}');
            },
          ),
          TextField(
            controller: sppController,
          ),
          ElevatedButton(
            onPressed: () async {
              await service.setSpp(spp: sppController.text);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('SPP set successfully'),
                  ),
                );
                sppController.clear();
                setState(() {
                  getOtp = service.generateOtp();
                });
              }
            },
            child: const Text('Submit SPP'),
          ),
        ],
      ),
    );
  }
}
