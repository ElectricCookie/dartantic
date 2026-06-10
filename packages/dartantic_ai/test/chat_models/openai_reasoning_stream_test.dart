import 'package:dartantic_ai/src/chat_models/openai_chat/openai_message_mappers_helpers.dart';
import 'package:openai_dart/openai_dart.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAI-compat reasoning stream helpers', () {
    test('reasoningTextFromOpenAIStreamDelta prefers reasoning_content', () {
      const delta = ChatCompletionStreamResponseDelta(
        reasoningContent: 'Let me think...',
        reasoning: 'ignored when content set',
      );
      expect(
        reasoningTextFromOpenAIStreamDelta(delta),
        'Let me think...',
      );
    });

    test('reasoningTextFromOpenAIStreamDelta falls back to reasoning', () {
      const delta = ChatCompletionStreamResponseDelta(
        reasoning: 'OpenRouter reasoning',
      );
      expect(
        reasoningTextFromOpenAIStreamDelta(delta),
        'OpenRouter reasoning',
      );
    });

    test('appendOpenAIStreamReasoning dedupes cumulative deltas', () {
      final buffer = StringBuffer();
      expect(
        appendOpenAIStreamReasoning(buffer, 'Hello'),
        'Hello',
      );
      expect(
        appendOpenAIStreamReasoning(buffer, 'Hello world'),
        ' world',
      );
      expect(buffer.toString(), 'Hello world');
    });

    test('appendOpenAIStreamReasoning ignores duplicate prefix', () {
      final buffer = StringBuffer()..write('done');
      expect(appendOpenAIStreamReasoning(buffer, 'done'), '');
      expect(buffer.toString(), 'done');
    });
  });
}
