import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:portable_ai_flutter/models/chat_model.dart';
import 'package:portable_ai_flutter/models/message_model.dart';
import 'package:portable_ai_flutter/services/llm_service.dart';
import 'package:portable_ai_flutter/theme/app_theme.dart';
import 'package:portable_ai_flutter/widgets/chat_bubble.dart';
import 'package:portable_ai_flutter/widgets/typing_indicator.dart';

/// Widget and model coverage for the chat surface.
///
/// The full app cannot be pumped in a plain widget test — it needs Hive and
/// path_provider platform channels — so these cover the leaf widgets and the
/// model logic behind them.
Widget _host(Widget child, {bool dark = false}) {
  return GetMaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<LlmService>(LlmService());
  });

  tearDown(Get.reset);

  group('ChatBubble', () {
    testWidgets('renders a user message with the person avatar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ChatBubble(
            message: MessageModel(
              role: MessageRole.user,
              content: 'What is the capital of France?',
            ),
          ),
        ),
      );

      expect(find.text('What is the capital of France?'), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    });

    testWidgets('renders an assistant message with the model avatar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ChatBubble(
            message: MessageModel(
              role: MessageRole.assistant,
              content: 'Paris.',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
    });

    testWidgets('renders an empty assistant message without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ChatBubble(
            message: MessageModel(role: MessageRole.assistant, content: ''),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark theme without throwing', (tester) async {
      await tester.pumpWidget(
        _host(
          ChatBubble(
            message: MessageModel(
              role: MessageRole.assistant,
              content: '# Heading\n\nSome **markdown** body.',
            ),
          ),
          dark: true,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('TypingIndicator', () {
    testWidgets('animates without throwing', (tester) async {
      await tester.pumpWidget(_host(const TypingIndicator()));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });

  group('ChatModel.autoTitle', () {
    test('takes the title from the first user message', () {
      final chat = ChatModel(id: '1')
        ..messages.add(
          MessageModel(role: MessageRole.user, content: 'Explain entropy'),
        );

      chat.autoTitle();

      expect(chat.title, 'Explain entropy');
    });

    test('truncates a long first message', () {
      final chat = ChatModel(id: '1')
        ..messages.add(
          MessageModel(role: MessageRole.user, content: 'a' * 100),
        );

      chat.autoTitle();

      expect(chat.title.length, 41); // 40 chars + ellipsis
      expect(chat.title, endsWith('…'));
    });

    test('does not overwrite a title the user already set', () {
      final chat = ChatModel(id: '1', title: 'My Chat')
        ..messages.add(
          MessageModel(role: MessageRole.user, content: 'Something else'),
        );

      chat.autoTitle();

      expect(chat.title, 'My Chat');
    });

    test('leaves the default in place when there is no user message', () {
      final chat = ChatModel(id: '1')
        ..messages.add(
          MessageModel(role: MessageRole.assistant, content: 'Hi there'),
        );

      chat.autoTitle();

      expect(chat.title, 'New Chat');
    });
  });

  group('MessageModel', () {
    test('maps onto the role/content shape the engine expects', () {
      final message = MessageModel(
        role: MessageRole.assistant,
        content: 'Hello',
      );

      expect(message.toLlamaMessage(), {
        'role': 'assistant',
        'content': 'Hello',
      });
    });

    test('role predicates are mutually exclusive', () {
      final user = MessageModel(role: MessageRole.user, content: 'x');
      final assistant = MessageModel(role: MessageRole.assistant, content: 'x');
      final system = MessageModel(role: MessageRole.system, content: 'x');

      expect([user.isUser, user.isAssistant, user.isSystem], [
        true,
        false,
        false,
      ]);
      expect([
        assistant.isUser,
        assistant.isAssistant,
        assistant.isSystem,
      ], [false, true, false]);
      expect([system.isUser, system.isAssistant, system.isSystem], [
        false,
        false,
        true,
      ]);
    });
  });
}
