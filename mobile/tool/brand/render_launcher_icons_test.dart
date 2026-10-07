// Renders the Android launcher icons from the in-app LollyMark painter, so
// the icon on the home screen is pixel-for-pixel the same artwork as the
// splash and app bar. Not part of the normal test run (lives under tool/,
// not test/); run it explicitly whenever the mark changes:
//
//   cd mobile && flutter test tool/brand/render_launcher_icons_test.dart
//
// Writes:
//   res/mipmap-*/ic_launcher.png             legacy icon (gradient tile)
//   res/mipmap-*/ic_launcher_foreground.png  adaptive foreground layer
// The adaptive background is res/drawable/ic_launcher_background.xml.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/theme/branding.dart';

const _densities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

void main() {
  testWidgets('render launcher icons from LollyMark', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final resDir = Directory('android/app/src/main/res');
    expect(resDir.existsSync(), isTrue, reason: 'run from the mobile/ directory');

    Future<void> render(Widget widget, double px, String relativePath) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: px, height: px, child: widget),
            ),
          ),
        ),
      );
      await tester.pump();
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('${resDir.path}/$relativePath');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    for (final entry in _densities.entries) {
      final density = entry.key;
      final scale = entry.value;

      // Legacy icon: 48dp tile, gradient background, mark with a little air.
      await render(
        LollyMark(
          size: 48 * scale,
          style: LollyMarkStyle.onGradient,
          withBackground: true,
          cornerRadiusFactor: 0.18,
          inset: 0.12,
        ),
        48 * scale,
        'mipmap-$density/ic_launcher.png',
      );

      // Adaptive foreground: 108dp canvas, the mark kept inside the 66dp
      // safe zone (inset 0.2 on each side = 64.8dp) over a transparent
      // background; the gradient comes from ic_launcher_background.xml.
      await render(
        LollyMark(size: 108 * scale, style: LollyMarkStyle.onGradient, inset: 0.2),
        108 * scale,
        'mipmap-$density/ic_launcher_foreground.png',
      );
    }

    expect(File('${resDir.path}/mipmap-xxxhdpi/ic_launcher_foreground.png').existsSync(), isTrue);
  });
}
