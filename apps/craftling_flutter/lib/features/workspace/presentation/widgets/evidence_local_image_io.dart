import 'dart:io';

import 'package:flutter/material.dart';

bool isLocalEvidenceImagePath(String path) {
  final String trimmed = path.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('data:image/')) {
    return false;
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    return true;
  }
  return RegExp(
    r'\.(png|jpe?g|webp|gif|bmp)$',
    caseSensitive: false,
  ).hasMatch(trimmed);
}

Widget buildLocalEvidenceImage({
  required String path,
  required BoxFit fit,
  double? height,
  double? width,
  required Widget Function() fallback,
}) {
  final String trimmed = path.trim();
  final Uri? uri = Uri.tryParse(trimmed);
  final File file = uri != null && uri.scheme == 'file'
      ? File.fromUri(uri)
      : File(trimmed);
  return Image.file(
    file,
    height: height,
    width: width,
    fit: fit,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => fallback(),
  );
}
