import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_mobile/features/location/presentation/location_selection_screen.dart';
import 'package:space_mobile/features/location/presentation/orbit_animation.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('native orbit fits $width in $brightness', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: RepaintBoundary(
              key: boundary,
              child: const OrbitOpeningScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(find.text('Finding your orbit...'), findsOneWidget);

        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(_visiblePixels(pixels!), greaterThan(4000));
        image.dispose();
      });
    }
  }

  testWidgets('native orbit scatters on drag and remains stable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: RepaintBoundary(child: OrbitAnimation(size: 220))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final target = find.byKey(const ValueKey('native-orbit-painter'));
    expect(target, findsOneWidget);

    await tester.dragFrom(tester.getCenter(target), const Offset(48, -34));
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}

int _visiblePixels(ByteData pixels) {
  var count = 0;
  final bytes = pixels.buffer.asUint8List();
  for (var index = 3; index < bytes.length; index += 4) {
    if (bytes[index] > 0) count++;
  }
  return count;
}
