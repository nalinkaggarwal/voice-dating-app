import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/theme/app_theme.dart';
import 'package:lolly/core/theme/branding.dart';

void main() {
  group('AppTheme', () {
    test('is dark-only on the ink canvas, magenta primary, coral as the voice accent', () {
      // "Midnight Bloom" is dark-only: both getters return the dark theme.
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.brightness, Brightness.dark);
        expect(theme.useMaterial3, isTrue);
        expect(theme.scaffoldBackgroundColor, AppTheme.ink);
        expect(theme.colorScheme.primary, AppTheme.magenta);
        expect(theme.colorScheme.tertiary, AppTheme.coral);
        expect(theme.textTheme.bodyLarge?.fontFamily, AppTheme.fontFamily);
      }
    });
  });

  group('LollyMark', () {
    testWidgets('paints at every progress step and size without throwing', (tester) async {
      for (final progress in [0.0, 0.2, 0.45, 0.7, 1.0]) {
        for (final style in LollyMarkStyle.values) {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: LollyMark(size: 96, progress: progress, style: style, withBackground: progress > 0.5),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: 'progress $progress, $style');
        }
      }
    });

    test('painter repaints only when something visible changed', () {
      final a = LollyMarkPainter(progress: 0.5, stickColor: Colors.white);
      final same = LollyMarkPainter(progress: 0.5, stickColor: Colors.white);
      final moved = LollyMarkPainter(progress: 0.6, stickColor: Colors.white);
      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(moved), isTrue);
    });
  });

  group('AppWordmark', () {
    testWidgets('renders the name with the accented suffix', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppWordmark(withMark: true))));
      expect(find.byType(LollyMark), findsOneWidget);
      final rich = tester.widget<Text>(find.byType(Text));
      expect(rich.textSpan!.toPlainText(), 'Lolly.ai');
    });
  });

  group('VoiceWaveform', () {
    testWidgets('animates while active and holds still when idle', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VoiceWaveform(active: true))));
      final before = tester.widgetList<Container>(find.byType(Container)).map((c) => c.constraints?.maxHeight).toList();
      await tester.pump(const Duration(milliseconds: 300));
      final after = tester.widgetList<Container>(find.byType(Container)).map((c) => c.constraints?.maxHeight).toList();
      expect(after, isNot(equals(before)));

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VoiceWaveform(active: false))));
      final idle1 = tester.widgetList<Container>(find.byType(Container)).map((c) => c.constraints?.maxHeight).toList();
      await tester.pump(const Duration(milliseconds: 300));
      final idle2 = tester.widgetList<Container>(find.byType(Container)).map((c) => c.constraints?.maxHeight).toList();
      expect(idle2, equals(idle1));
    });
  });
}
