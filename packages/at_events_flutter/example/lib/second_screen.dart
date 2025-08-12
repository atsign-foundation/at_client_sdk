import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_events_flutter/at_events_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' show dotenv;

import 'main.dart';

class SecondScreen extends StatefulWidget {
  const SecondScreen({Key? key}) : super(key: key);

  @override
  State<SecondScreen> createState() => _SecondScreenState();
}

class _SecondScreenState extends State<SecondScreen> {
  String? activeAtSign;
  GlobalKey<ScaffoldState>? scaffoldKey;
  bool? isAuthenticated;
  List<EventKeyLocationModel> events = [];

  /// Get the AtClientManager instance
  var atClientManager = AtClientManager.getInstance();
  late AtClientPreference atClientPreference;
  @override
  void initState() {
    scaffoldKey = GlobalKey<ScaffoldState>();
    super.initState();

    try {
      activeAtSign = atClientManager.atClient.getCurrentAtSign();
      initializeEventService();
      isAuthenticated = true;
    } catch (e) {
      isAuthenticated = false;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return alertDialogContent();
          },
        );
      });
    }
  }

  void updateEvents(List<EventKeyLocationModel> events) {
    setState(() {
      events = events;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Second Screen')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            height: 20.0,
          ),
          Container(
            padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
            child: Center(
              child: Text(
                'Welcome $activeAtSign!',
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(
            height: 20.0,
          ),
          TextButton(
            onPressed: () {
              bottomSheet(CreateEvent(atClientManager), MediaQuery.of(context).size.height * 0.9);
            },
            child: const SizedBox(
              height: 40,
              child: Text('Create event', style: TextStyle(color: Colors.black)),
            ),
          ),
          const SizedBox(
            height: 20.0,
          ),
          Expanded(
            child: ListView.separated(
                itemBuilder: (BuildContext context, int index) {
                  return InkWell(
                    onTap: () {
                      HomeEventService()
                          .onEventModelTap(events[index].eventNotificationModel!, events[index].haveResponded);
                    },
                    child: DisplayTile(
                      atsignCreator: events[index].eventNotificationModel!.atsignCreator,
                      number: events[index].eventNotificationModel!.group!.members!.length,
                      title: 'Event - ${events[index].eventNotificationModel!.title!}',
                      subTitle: HomeEventService().getSubTitle(events[index].eventNotificationModel!),
                      semiTitle: HomeEventService()
                          .getSemiTitle(events[index].eventNotificationModel!, events[index].haveResponded),
                      showRetry: HomeEventService().calculateShowRetry(events[index]),
                      onRetryTapped: () {
                        HomeEventService().onEventModelTap(events[index].eventNotificationModel!, false);
                      },
                    ),
                  );
                },
                separatorBuilder: (BuildContext context, int index) {
                  return const Divider(
                    color: Colors.grey,
                  );
                },
                itemCount: events.length),
          )
        ],
      ),
    );
  }

  void initializeEventService() {
    initialiseEventService(NavService.navKey,
        mapKey: dotenv.get('MAP_KEY', fallback: ''),
        apiKey: dotenv.get('API_KEY', fallback: ''),
        rootDomain: 'root.atsign.org',
        streamAlternative: updateEvents);
  }

  void bottomSheet(
    T,
    double height,
  ) async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const StadiumBorder(),
        builder: (BuildContext context) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12.0),
                topRight: Radius.circular(12.0),
              ),
            ),
            child: T,
          );
        });
  }

  Widget alertDialogContent() {
    return AlertDialog(
      title: const Text('you are not authenticated'),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
          child: const Text('Ok', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}
