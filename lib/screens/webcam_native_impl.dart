import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'webcam_screen.dart';

Widget buildNativeWebcamWidget({required CamConfig cam}) {
  return _NativeWebcamView(cam: cam);
}

class _NativeWebcamView extends StatefulWidget {
  final CamConfig cam;
  const _NativeWebcamView({required this.cam});

  @override
  State<_NativeWebcamView> createState() => _NativeWebcamViewState();
}

class _NativeWebcamViewState extends State<_NativeWebcamView> {
  late WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() { _loading = true; _error = null; }),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (err) => setState(() {
          _error = err.description;
          _loading = false;
        }),
      ));

    if (widget.cam.isMjpeg) {
      final html = '''
        <!DOCTYPE html>
        <html>
        <body style="margin:0;padding:0;background:#000;display:flex;justify-content:center;align-items:center;height:100vh;">
          <img src="${widget.cam.url}" style="width:100%;height:auto;max-height:100%;object-fit:contain;" />
        </body>
        </html>
      ''';
      _controller.loadHtmlString(html);
    } else {
      _controller.loadRequest(Uri.parse(widget.cam.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6))),
        if (_error != null)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('❌', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 8),
                const Text('Stream Error', style: TextStyle(color: Colors.red, fontSize: 16)),
                Text(_error!, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: _initWebView, child: const Text('Retry')),
              ],
            ),
          ),
      ],
    );
  }
}
