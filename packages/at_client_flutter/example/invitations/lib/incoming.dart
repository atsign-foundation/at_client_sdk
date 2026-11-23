import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client_mixins.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:play_install_referrer/play_install_referrer.dart';

/// The invitation waiting to be opened, from whichever route it arrived by.
///
/// A link opens the app directly when it is installed. When it was not, the
/// invitation survives the install on Android through the Play install
/// referrer, which the landing page fills in, and on iOS through the
/// clipboard, which the landing page's "Copy invitation" button fills in.
class Incoming extends ValueNotifier<InvitationLink?> {
  static final Incoming instance = Incoming._();

  Incoming._() : super(null);

  StreamSubscription<Uri>? _links;

  /// Written once the install referrer's invitation has been opened, since
  /// Play keeps offering the same referrer long after the install.
  File? _referrerOpened;
  String? _referrerId;

  /// Starts listening for invitation links, and checks the install referrer
  /// until its invitation has been opened.
  Future<void> start() async {
    final appLinks = AppLinks();
    _links = appLinks.uriLinkStream.listen((uri) => offer(uri.toString()));
    if (!kIsWeb && Platform.isAndroid) await _fromInstallReferrer();
  }

  Future<void> stop() async => _links?.cancel();

  /// Takes [text] as the pending invitation if it is one. Returns whether it
  /// was.
  bool offer(String text) {
    try {
      value = InvitationLink.parse(text);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Marks the pending invitation as dealt with.
  void clear() {
    if (value != null && value!.id == _referrerId) {
      _referrerOpened?.createSync(recursive: true);
    }
    value = null;
  }

  Future<void> _fromInstallReferrer() async {
    final opened = File(
      '${(await getApplicationSupportDirectory()).path}/referrer_opened',
    );
    if (opened.existsSync()) return;
    final ReferrerDetails details;
    try {
      details = await PlayInstallReferrer.installReferrer;
    } on PlatformException {
      // NOTE: a sideloaded or emulator install has no Play referrer.
      return;
    } on MissingPluginException {
      return;
    }
    final Map<String, String> referrer;
    try {
      referrer = Uri.splitQueryString(details.installReferrer ?? '');
    } on ArgumentError {
      // NOTE: the referrer is whatever the install link carried.
      return;
    }
    final invitation = referrer['invitation'];
    if (invitation != null && offer(invitation)) {
      _referrerOpened = opened;
      _referrerId = value!.id;
    }
  }
}
