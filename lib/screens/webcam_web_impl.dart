import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

Widget buildWebcamWidget({required Key key, required String url, required bool isMjpeg}) {
  return _WebWebcam(key: key, url: url, isMjpeg: isMjpeg);
}

class _WebWebcam extends StatefulWidget {
  final String url;
  final bool isMjpeg;

  const _WebWebcam({super.key, required this.url, required this.isMjpeg});

  @override
  State<_WebWebcam> createState() => _WebWebcamState();
}

class _WebWebcamState extends State<_WebWebcam> {
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'webcam-${widget.url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
    _register();
  }

  void _register() {
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      if (widget.isMjpeg) {
        final img = html.ImageElement()
          ..src = widget.url
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'contain'
          ..style.backgroundColor = '#000';
        return img;
      } else {
        final iframe = html.IFrameElement()
          ..src = widget.url
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..allow = 'autoplay; encrypted-media'
          ..allowFullscreen = true;
        return iframe;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
