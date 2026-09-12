import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_mobile/main.dart';
import 'package:space_mobile/services/api_service.dart';
import 'package:space_mobile/services/chat_socket.dart';

void main() {
  test('poll results preserve counts and current vote', () {
    final poll = PollData.fromJson({
      'options': ['Yes', 'No'],
      'counts': [2, 1],
      'selected': 1,
    });
    expect(poll.total, 3);
    expect(poll.selected, 1);
    expect(
      ChatSocket.decode('{"type":"poll_updated","message_id":"p1"}'),
      isA<WsPollUpdatedEvent>(),
    );
  });

  testWidgets('poll rejects duplicate options and submits valid choices', (
    tester,
  ) async {
    List<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PollComposerDialog(
            onCreate: (question, options) async {
              saved = [question, ...options];
            },
          ),
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Lunch?');
    await tester.enterText(fields.at(1), 'Pizza');
    await tester.enterText(fields.at(2), ' pizza ');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(saved, isNull);
    expect(
      find.text('Enter a question and distinct, non-empty options.'),
      findsOneWidget,
    );
    await tester.enterText(fields.at(2), 'Salad');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(saved, ['Lunch?', 'Pizza', 'Salad']);
  });

  testWidgets('chat plus opens its action without a media picker', (
    tester,
  ) async {
    final controller = TextEditingController();
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            onSend: () {},
            onAdd: () => opened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Chat options'));
    expect(opened, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
