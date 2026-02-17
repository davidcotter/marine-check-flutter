import 'package:flutter/material.dart';
import 'webcam_screen.dart';

Widget buildNativeWebcamWidget({required CamConfig cam}) {
  return const Center(
    child: Text('Webcam not available', style: TextStyle(color: Colors.white)),
  );
}
