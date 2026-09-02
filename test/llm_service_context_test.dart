import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:portable_ai_flutter/services/llm_service.dart';

LlamaChatMessage _msg(LlamaChatRole role, String text) =>
    LlamaChatMessage.fromText(role: role, text: text);

void main() {
  late LlmService llm;

  setUp(() {
    llm = LlmService();
    llm.contextTokens.value = 1024;
  });

  group('trimToContext', () {
    test('leaves a short conversation untouched', () {
      final messages = [
        _msg(LlamaChatRole.system, 'You are helpful.'),
        _msg(LlamaChatRole.user, 'Hi'),
        _msg(LlamaChatRole.assistant, 'Hello!'),
        _msg(LlamaChatRole.user, 'How are you?'),
      ];

      final trimmed = llm.trimToContext(messages);

      expect(trimmed, hasLength(messages.length));
      expect(llm.lastTrimmedMessages.value, 0);
    });

    test('drops the oldest turns when the history overflows', () {
      // 1024-token context, 512 reserved -> ~512 tokens of room.
      // Each turn below is ~1800 chars, roughly 500 tokens.
      final messages = <LlamaChatMessage>[
        _msg(LlamaChatRole.system, 'You are helpful.'),
        for (var i = 0; i < 6; i++)
          _msg(
            i.isEven ? LlamaChatRole.user : LlamaChatRole.assistant,
            'turn $i ${'x' * 1800}',
          ),
      ];

      final trimmed = llm.trimToContext(messages);

      expect(trimmed.length, lessThan(messages.length));
      expect(llm.lastTrimmedMessages.value, greaterThan(0));
    });

    test('always keeps system messages', () {
      final messages = <LlamaChatMessage>[
        _msg(LlamaChatRole.system, 'Stay in character.'),
        for (var i = 0; i < 8; i++)
          _msg(LlamaChatRole.user, 'turn $i ${'y' * 2000}'),
      ];

      final trimmed = llm.trimToContext(messages);

      expect(
        trimmed.where((m) => m.role == LlamaChatRole.system),
        hasLength(1),
        reason: 'the system prompt must survive trimming',
      );
    });

    test('always keeps the most recent turn, even if oversized', () {
      final huge = 'z' * 200000;
      final messages = [
        _msg(LlamaChatRole.system, 'You are helpful.'),
        _msg(LlamaChatRole.user, 'old ${'a' * 5000}'),
        _msg(LlamaChatRole.user, huge),
      ];

      final trimmed = llm.trimToContext(messages);

      expect(trimmed.last.content, huge);
      expect(
        trimmed.where((m) => m.role != LlamaChatRole.system),
        hasLength(1),
      );
    });

    test('a larger context window keeps more history', () {
      final messages = <LlamaChatMessage>[
        for (var i = 0; i < 6; i++)
          _msg(LlamaChatRole.user, 'turn $i ${'x' * 1800}'),
      ];

      llm.contextTokens.value = 1024;
      final small = llm.trimToContext(messages).length;

      llm.contextTokens.value = 8192;
      final large = llm.trimToContext(messages).length;

      expect(large, greaterThan(small));
    });

    test('reports how many messages were dropped', () {
      final messages = <LlamaChatMessage>[
        for (var i = 0; i < 5; i++)
          _msg(LlamaChatRole.user, 'turn $i ${'x' * 2000}'),
      ];

      final trimmed = llm.trimToContext(messages);

      expect(
        llm.lastTrimmedMessages.value,
        messages.length - trimmed.length,
      );
    });
  });
}
