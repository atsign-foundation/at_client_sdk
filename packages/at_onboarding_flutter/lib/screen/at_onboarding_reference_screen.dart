import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_sync_ui_flutter/at_sync_material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Displays onboarding reference screens
/// It uses weview to display the [url]
class AtOnboardingReferenceScreen extends StatefulWidget {
  /// Static method to navigate to this screen
  static push({
    required BuildContext context,
    required String? url,
    required String? title,
    required AtOnboardingConfig config,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AtOnboardingReferenceScreen(
          url: url,
          title: title,
          config: config,
        ),
      ),
    );
  }

  /// The URL to display on the screen
  final String? url;

  /// The title for the screen
  final String? title;

  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingReferenceScreen({
    Key? key,
    this.url,
    this.title,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingReferenceScreen> createState() =>
      _AtOnboardingReferenceScreenState();
}

class _AtOnboardingReferenceScreenState
    extends State<AtOnboardingReferenceScreen> {
  late bool isLoading;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers = {
    Factory(() => EagerGestureRecognizer())
  };
  late WebViewController webViewController;

  @override
  void initState() {
    super.initState();
    // Enable hybrid composition.
    isLoading = true;
    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {},
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {},
        ),
      )
      ..loadRequest(Uri.parse(widget.url ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      textTheme: widget.config.theme?.textTheme,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title ?? AtOnboardingLocalizations.current.title_FAQ,
          ),
          centerTitle: true,
        ),
        backgroundColor: Colors.white,
        body: Stack(
          children: <Widget>[
            WebViewWidget(
              controller: webViewController,
              gestureRecognizers: gestureRecognizers,
            ),
            isLoading
                ? const Center(
                    child: AtSyncIndicator(),
                  )
                : const SizedBox()
          ],
        ),
      ),
    );
  }
}
