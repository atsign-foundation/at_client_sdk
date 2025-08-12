import 'package:at_backupkey_flutter/utils/color_constants.dart';
import 'package:at_onboarding_flutter/localizations/generated/l10n.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// This screen is for showing WebView during the onboarding process
class AtOnboardingWebviewScreen extends StatefulWidget {
  /// The URL to be displayed
  final String? url;

  /// The title of the screen
  final String? title;

  const AtOnboardingWebviewScreen({
    Key? key,
    this.url,
    this.title,
  }) : super(key: key);

  @override
  State<AtOnboardingWebviewScreen> createState() =>
      _AtOnboardingWebviewScreenState();
}

class _AtOnboardingWebviewScreenState extends State<AtOnboardingWebviewScreen> {
  late bool isLoading;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? AtOnboardingLocalizations.current.title_FAQ,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.normal,
          ),
        ),
        elevation: 1.0,
        centerTitle: true,
        backgroundColor: ColorConstants.appColor,
      ),
      body: Stack(
        children: <Widget>[
          WebViewWidget(
            controller: webViewController,
          ),
          isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ColorConstants.appColor,
                    ),
                  ),
                )
              : const SizedBox()
        ],
      ),
    );
  }
}
