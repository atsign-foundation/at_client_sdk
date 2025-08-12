// ignore_for_file: must_call_super

import 'package:at_notify_flutter/models/notify_model.dart';
import 'package:at_notify_flutter/services/notify_service.dart';
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';

class NotifyScreen extends StatefulWidget {
  final NotifyService? notifyService;
  final bool isAuthorAtSign;
  final String? atSign;

  const NotifyScreen({
    Key? key,
    this.notifyService,
    this.isAuthorAtSign = false,
    this.atSign = '',
  }) : super(key: key);

  @override
  _NotifyScreenState createState() => _NotifyScreenState();
}

class _NotifyScreenState extends State<NotifyScreen>
    with AutomaticKeepAliveClientMixin {
  ScrollController? _scrollController;
  late int _selectedDate;

  @override
  void initState() {
    _selectedDate = 1;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      /// fetch list of notifications
      await widget.notifyService!.getNotifies(
        atsign: widget.atSign,
        days: _selectedDate,
      );
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      body: StreamBuilder<List<Notify>>(
        stream: widget.notifyService!.notifyStream,
        initialData: widget.notifyService!.notifies,
        builder: (context, snapshot) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: (snapshot.data?.length ?? 0) > 0 ? 50 : 0,
              ),
              Text(
                'No of Days: $_selectedDate',
                style: TextStyle(
                  color: const Color(0xFF000000),
                  fontSize: 16.toFont,
                ),
              ),
              Slider(
                activeColor: Theme.of(context).primaryColor,
                inactiveColor: Colors.grey[200],
                value: _selectedDate.toDouble(),
                min: 1,
                max: 30,
                divisions: 30,
                label: 'Select days',
                onChanged: (double value) {
                  setState(() {
                    _selectedDate = value.toInt();
                  });
                },
              ),
              TextButton(
                onPressed: () async {
                  widget.notifyService!.getNotifies(
                    atsign: widget.atSign,
                    days: _selectedDate,
                  );
                },
                child: const Text(
                  'Get notifications',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 22.0),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Notifications: ',
                      style: TextStyle(fontSize: 18),
                    )),
              ),
              const SizedBox(
                height: 10,
              ),
              (snapshot.connectionState == ConnectionState.waiting)
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : (snapshot.data == null || snapshot.data!.isEmpty)
                      ? const Center(
                          child: Text('No notifications found'),
                        )
                      : Expanded(
                          child: ListView.separated(
                            controller: _scrollController,
                            shrinkWrap: true,
                            itemCount: snapshot.data?.length ?? 0,
                            padding:
                                EdgeInsets.symmetric(vertical: 12.toHeight),
                            itemBuilder: (context, index) {
                              return Container(
                                padding: EdgeInsets.symmetric(
                                    vertical: 12.toHeight,
                                    horizontal: 12.toWidth),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Sender: ${snapshot.data?[index].atSign}'),
                                    const SizedBox(height: 5),
                                    snapshot.data![index].time != null
                                        ? Text(
                                            'Date : ${DateTime.fromMillisecondsSinceEpoch(snapshot.data![index].time!)}',
                                          )
                                        : const SizedBox(),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Value:  ${snapshot.data?[index].message}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (context, index) {
                              return const Divider();
                            },
                          ),
                        )
            ],
          );
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
