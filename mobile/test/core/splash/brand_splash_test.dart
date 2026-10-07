import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/splash/brand_splash.dart';
import 'package:lolly/core/theme/branding.dart';

void main() {
  setUp(BrandSplash.resetForTesting);

  testWidgets('covers the app during the sequence, then gets out of the way', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrandSplash(
          duration: Duration(milliseconds: 400),
          child: Scaffold(body: Center(child: Text('app'))),
        ),
      ),
    );

    // Frame 0: the app is already built underneath, the overlay is on top.
    expect(find.text('app'), findsOneWidget);
    expect(find.byType(BrandSplashOverlay), findsOneWidget);
    expect(find.byType(LollyMark), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BrandSplashOverlay), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(BrandSplashOverlay), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('a re-created instance resumes instead of replaying', (tester) async {
    // The widget-test clock does not move DateTime.now(); drive the
    // splash's own clock so "later in the same process" can be simulated.
    var now = DateTime(2026, 10, 7, 12);
    BrandSplash.clock = () => now;

    await tester.pumpWidget(
      const MaterialApp(
        home: BrandSplash(duration: Duration(milliseconds: 400), child: SizedBox()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(BrandSplashOverlay), findsNothing);

    // Same process, new widget, wall clock past the duration: no overlay.
    now = now.add(const Duration(seconds: 1));
    await tester.pumpWidget(
      const MaterialApp(
        home: BrandSplash(key: ValueKey('second'), duration: Duration(milliseconds: 400), child: SizedBox()),
      ),
    );
    expect(find.byType(BrandSplashOverlay), findsNothing);
  });

  testWidgets('the overlay renders every element at the final frame', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandSplashOverlay(t: 0.8)));
    expect(find.byType(LollyMark), findsOneWidget);
    expect(find.byType(AppWordmark), findsOneWidget);
    expect(find.text(kAppTagline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
