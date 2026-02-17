import 'package:flutter/material.dart';

Widget buildWebcamWidget({required Key key, required String url, required bool isMjpeg}) {
  return const Center(
    child: Text('Webcam not available on this platform', style: TextStyle(color: Colors.white)),
  );
}
