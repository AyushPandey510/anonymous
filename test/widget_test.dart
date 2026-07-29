import 'package:flutter_test/flutter_test.dart';

import 'package:space_mobile/main.dart';

void main() {
  testWidgets('renders Space loading state', (tester) async {
    await tester.pumpWidget(const SpaceApp());

    expect(find.byType(SpaceApp), findsOneWidget);
  });
}
