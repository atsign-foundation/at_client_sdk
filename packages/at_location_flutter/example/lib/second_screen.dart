import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_location_flutter/at_location_flutter.dart';
import 'package:at_location_flutter/common_components/custom_toast.dart';
import 'package:at_location_flutter/location_modal/key_location_model.dart';
import 'package:at_location_flutter/service/key_stream_service.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' show dotenv;
import 'package:latlong2/latlong.dart';

import 'main.dart';

class SecondScreen extends StatefulWidget {
  const SecondScreen({Key? key}) : super(key: key);

  @override
  State<SecondScreen> createState() => _SecondScreenState();
}

class _SecondScreenState extends State<SecondScreen> {
  AtAuthService? atClientService;
  GlobalKey<ScaffoldState>? scaffoldKey;
  String? activeAtSign, receiver;
  Stream<List<KeyLocationModel>?>? newStream;
  MapController mapController = MapController();

  /// Get the AtClientManager instance
  var atClientManager = AtClientManager.getInstance();
  @override
  void initState() {
    try {
      super.initState();
      getAtSignAndInitializeLocation();
      scaffoldKey = GlobalKey<ScaffoldState>();
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return alertDialogContent();
          },
        );
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        title: const Text('Second Screen'),
      ),
      body: Center(
        child: ListView(
          // mainAxisSize: MainAxisSize.min,
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
              child: Text(
                'Welcome $activeAtSign!',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // any logic
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (BuildContext context) => const HomeScreen(),
                ));
              },
              child: const Text('Show maps'),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Type an atSign',
                  enabledBorder: InputBorder.none,
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey[400]),
                ),
                onChanged: (val) {
                  receiver = val;
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    var result = await checkAtsign();
                    if (!result && context.mounted) {
                      CustomToast().show('Atsign not valid', context);
                      return;
                    }
                    if (!result) return;
                    await sendShareLocationNotification(receiver!, 30);
                  },
                  child: const Text('Send Location '),
                ),
                ElevatedButton(
                  onPressed: () async {
                    var result = await checkAtsign();
                    if (!result && context.mounted) {
                      CustomToast().show('Atsign not valid', context);
                      return;
                    }
                    if (!result) return;
                    await sendRequestLocationNotification(receiver!);
                  },
                  child: const Text('Request Location'),
                ),
              ],
            ),
            const SizedBox(
              height: 30,
            ),
            ElevatedButton(
              onPressed: () async {
                var result = await checkAtsign();
                if (context.mounted) {
                  if (!result) {
                    CustomToast().show('Atsign not valid', context);
                    return;
                  }
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (BuildContext context) => AtLocationFlutterPlugin(
                      [receiver],
                      calculateETA: true,
                      addCurrentUserMarker: true,
                      // etaFrom: LatLng(44, -112),
                      // textForCenter: 'Final',
                    ),
                  ));
                }
              },
              child: const Text('Track Location '),
            ),
            ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (BuildContext context) => showLocation(UniqueKey(), mapController, locationList: [
                    const LatLng(30, 45),
                    const LatLng(40, 45),
                  ]),
                ));
              },
              child: const Text('Show multiple points '),
            ),
            const SizedBox(
              height: 30,
            ),
            const Center(
              child: Text(
                'Notifications:',
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: StreamBuilder(
                  stream: KeyStreamService().atNotificationsStream,
                  builder: (context, AsyncSnapshot<List<KeyLocationModel>> snapshot) {
                    if (snapshot.connectionState == ConnectionState.active) {
                      if (snapshot.hasError) {
                        return const Text('error');
                      } else {
                        return (snapshot.data?.isNotEmpty ?? false)
                            ? renderNotifications(snapshot.data!)
                            : const Text('No Data');
                      }
                    } else {
                      if (KeyStreamService().allLocationNotifications.isNotEmpty) {
                        return renderNotifications(KeyStreamService().allLocationNotifications);
                      }
                      return const Text('No Data');
                    }
                  }),
            )
          ],
        ),
      ),
    );
  }

  Widget renderNotifications(List<KeyLocationModel> data) {
    return Column(
        children: data.map((notification) {
      return Padding(
        padding: const EdgeInsets.all(14.0),
        child: Text(
          '${data.indexOf(notification) + 1}. ${notification.locationNotificationModel!.key}',
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.left,
        ),
      );
    }).toList());
  }

  Future<bool> checkAtsign() async {
    if (receiver == null) {
      return false;
    } else if (!receiver!.contains('@')) {
      receiver = '@${receiver!}';
    }
    var checkPresence =
        // ignore: deprecated_member_use
        await AtLookupImpl.findSecondary(receiver!, 'root.atsign.org', 64);
    return checkPresence != null;
  }

  Widget alertDialogContent() {
    return AlertDialog(
      title: const Text('you are not authenticated.'),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
          child: const Text(
            'Ok',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }

  getAtSignAndInitializeLocation() {
    activeAtSign = AtClientManager.getInstance().atClient.getCurrentAtSign();
    initializeLocationService(
      NavService.navKey,
      mapKey: dotenv.get('MAP_KEY', fallback: ''),
      apiKey: dotenv.get('API_KEY', fallback: ''),
      showDialogBox: true,
    );
    newStream = getAllNotification() as Stream<List<KeyLocationModel>?>?;
  }
}
