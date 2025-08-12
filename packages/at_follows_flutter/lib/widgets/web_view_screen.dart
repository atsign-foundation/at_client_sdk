import 'package:at_follows_flutter/utils/app_constants.dart';
import 'package:at_follows_flutter/utils/color_constants.dart';
import 'package:at_follows_flutter/widgets/custom_appbar.dart';
import 'package:flutter/material.dart';
import 'package:at_utils/at_logger.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  WebViewScreen({
    required this.url,
    required this.title,
  });

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late bool isLoading;
  var _logger = AtSignLogger('WebView Widget');
  late WebViewController webViewController;

  @override
  void initState() {
    super.initState();
    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
          },
          onNavigationRequest: (navReq) async {
            if (navReq.url.startsWith(AppConstants.appUrl)) {
              _logger.info('Navigation decision is taken by urlLauncher');
              await _launchURL(navReq.url);
              return NavigationDecision.prevent;
            }
            _logger.info('Navigation decision is taken by webView');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    isLoading = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        showBackButton: true,
        title: widget.title,
        showTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(
            controller: webViewController,
          ),
          isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color?>(
                      ColorConstants.activeColor,
                    ),
                  ),
                )
              : SizedBox()
        ],
      ),
    );
  }

  _launchURL(String url) async {
    // url = Uri.encodeFull(url);
    if (await canLaunchUrlString(url)) {
      Navigator.pop(context);
      Navigator.pop(context);
      await launchUrlString(url);
    } else {
      _logger.severe('unable to launch $url');
    }
  }
}
