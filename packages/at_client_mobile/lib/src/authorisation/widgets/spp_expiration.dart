import 'dart:async';

import 'package:duration/duration.dart';
import 'package:flutter/material.dart';

class SppExpiration extends StatefulWidget {
  const SppExpiration({
    required this.expiryTime,
    required this.onExpiry,
    super.key,
  });

  final DateTime expiryTime;
  final VoidCallback onExpiry;

  @override
  SppExpirationState createState() => SppExpirationState();
}

class SppExpirationState extends State<SppExpiration> {
  DateTime get expiryTime => widget.expiryTime;

  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      _updateExpiryTime,
    );
  }

  void _updateExpiryTime(Timer timer) {
    if (DateTime.now().isAfter(expiryTime)) {
      timer.cancel();
      widget.onExpiry();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Text(
        'Current pin expires in ${expiryTime.difference(DateTime.now()).pretty()}',
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
    );
  }
}
