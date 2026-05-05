import 'package:flutter/material.dart';

bool isLocalEvidenceImagePath(String path) => false;

Widget buildLocalEvidenceImage({
  required String path,
  required BoxFit fit,
  double? height,
  double? width,
  required Widget Function() fallback,
}) {
  return fallback();
}
