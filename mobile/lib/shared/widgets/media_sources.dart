import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// Turns a media URL from the API into something playable / displayable.
/// Real builds only ever see http(s) URLs (signed S3 links); the demo
/// build (lib/demo/) also uses `asset:<path>` for bundled clips/photos and
/// `file:<path>` for the user's own recorded voice notes.
Source audioSourceFor(String url) {
  if (url.startsWith('asset:')) {
    // audioplayers' AssetSource resolves relative to `assets/`.
    final path = url.substring('asset:'.length);
    return AssetSource(path.startsWith('assets/') ? path.substring('assets/'.length) : path);
  }
  if (url.startsWith('file:')) return DeviceFileSource(url.substring('file:'.length));
  return UrlSource(url);
}

ImageProvider imageProviderFor(String url) {
  if (url.startsWith('asset:')) return AssetImage(url.substring('asset:'.length));
  if (url.startsWith('file:')) return FileImage(File(url.substring('file:'.length)));
  return NetworkImage(url);
}
