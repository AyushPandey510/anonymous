import 'package:flutter_test/flutter_test.dart';

import 'package:space_mobile/main.dart';

void main() {
  testWidgets('renders Space home screen', (tester) async {
    await tester.pumpWidget(const SpaceApp());

    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('Startup Engineering'), findsWidgets);
    expect(find.text('Join Space'), findsOneWidget);
  });
}
