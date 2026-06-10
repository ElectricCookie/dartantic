import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

/// Mimics OpenAI chat streaming: text deltas during the stream, then a final
/// tools-only chunk (text already streamed).
class OpenAIToolStreamModel extends ChatModel<ChatModelOptions> {
  OpenAIToolStreamModel({required super.name})
    : super(defaultOptions: const ChatModelOptions());

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    ChatModelOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    final hasToolResults = messages.any(
      (m) => m.parts.whereType<ToolPart>().any(
        (p) => p.kind == ToolPartKind.result,
      ),
    );

    if (!hasToolResults) {
      for (final delta in ['Now I have the full picture. ', 'Let me act.']) {
        final chunk = ChatMessage(
          role: ChatMessageRole.model,
          parts: [TextPart(delta)],
        );
        yield ChatResult<ChatMessage>(
          output: chunk,
          messages: [chunk],
          finishReason: FinishReason.unspecified,
          metadata: const {},
          usage: null,
        );
      }

      const toolCall = ToolPart.call(
        id: 'call_1',
        name: 'searchTools',
        arguments: {'query': 'notes'},
      );
      const toolsOnly = ChatMessage(
        role: ChatMessageRole.model,
        parts: [toolCall],
      );

      yield ChatResult<ChatMessage>(
        output: const ChatMessage(role: ChatMessageRole.model, parts: []),
        messages: [toolsOnly],
        finishReason: FinishReason.toolCalls,
        metadata: const {},
        usage: const LanguageModelUsage(),
      );
      return;
    }

    const finalText = ChatMessage(
      role: ChatMessageRole.model,
      parts: [TextPart('Done.')],
    );
    yield ChatResult<ChatMessage>(
      output: finalText,
      messages: [finalText],
      finishReason: FinishReason.stop,
      metadata: const {},
      usage: const LanguageModelUsage(),
    );
  }

  @override
  void dispose() {}
}

class OpenAIToolStreamProvider
    extends
        Provider<
          ChatModelOptions,
          EmbeddingsModelOptions,
          MediaGenerationModelOptions
        > {
  OpenAIToolStreamProvider()
    : super(
        name: 'openai-tool-stream-test',
        displayName: 'OpenAI Tool Stream Test',
        defaultModelNames: const {ModelKind.chat: 'test-model'},
      );

  @override
  ChatModel<ChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    ChatModelOptions? options,
  }) => OpenAIToolStreamModel(name: name ?? 'test-model');

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw UnsupportedError('not needed');

  @override
  Stream<ModelInfo> listModels() async* {}

  @override
  MediaGenerationModel<MediaGenerationModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    MediaGenerationModelOptions? options,
  }) => throw UnsupportedError('not needed');
}

bool _hasExactHalvesDuplication(String text) {
  if (text.length < 20) {
    return false;
  }
  final halfLength = text.length ~/ 2;
  return text.substring(0, halfLength).trim() ==
      text.substring(halfLength, halfLength * 2).trim();
}

void main() {
  group('OpenAI tool stream duplication', () {
    test('agent.send does not duplicate text across tool iterations', () async {
      final provider = OpenAIToolStreamProvider();
      final agent = Agent.forProvider(
        provider,
        chatModelName: 'test-model',
        tools: [
          Tool(
            name: 'searchTools',
            description: 'search',
            inputSchema: JsonSchema.create({'type': 'object'}),
            onCall: (_) async => 'ok',
          ),
        ],
      );

      final streamed = <String>[];
      final messages = <ChatMessage>[];

      await for (final chunk in agent.sendStream('cleanup')) {
        if (chunk.output.isNotEmpty) {
          streamed.add(chunk.output);
        }
        messages.addAll(chunk.messages);
      }

      final accumulated = streamed.join();

      expect(
        _hasExactHalvesDuplication(accumulated),
        isFalse,
        reason: 'streamed chunks duplicated text',
      );
      expect(
        accumulated,
        equals('Now I have the full picture. Let me act.Done.'),
        reason: 'streamed output should match deltas plus final reply',
      );
      expect(
        accumulated,
        isNot(contains('Now I have the full picture. Now I have the full picture.')),
        reason: 'planning paragraph should not repeat back-to-back',
      );
    });
  });
}
