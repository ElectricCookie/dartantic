import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openai_dart/openai_dart.dart' as o;
import 'package:test/test.dart';

/// Builds an [OpenAIChatModel] whose SSE stream is served by [respondBody].
OpenAIChatModel _modelWithStream(String respondBody) {
  final mock = MockClient.streaming((request) async {
    final stream = Stream<Uint8List>.fromIterable([
      Uint8List.fromList(utf8.encode(respondBody)),
    ]);
    final resp = http.StreamedResponse(
      stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
    return resp;
  });
  return OpenAIChatModel(
    name: 'gpt-4o-mini',
    apiKey: 'test-key',
    baseUrl: Uri.parse('https://api.openai.com'),
    client: mock,
    tools: const [],
  );
}

String _sse(String payload) => 'data: $payload\n\n';

/// Mimics OpenAI chat-completions streaming for a single tool call: first the
/// id+name delta with empty args, then two partial JSON argument deltas, then a
/// finish chunk.
String _toolCallSse({
  String callId = 'call_1',
  String name = 'search',
  List<String> argDeltas = const ['{"q": "te', 'st"}'],
}) {
  final buffer = StringBuffer()
    ..write(
      _sse(
        json.encode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion.chunk',
          'created': 1,
          'model': 'gpt-4o-mini',
          'choices': [
            {'index': 0, 'delta': {'role': 'assistant', 'content': ''}, 'finish_reason': null},
          ],
        }),
      ),
    );
  buffer.write(
    _sse(
      json.encode({
        'id': 'chatcmpl-1',
        'object': 'chat.completion.chunk',
        'created': 1,
        'model': 'gpt-4o-mini',
        'choices': [
          {
            'index': 0,
            'delta': {
              'tool_calls': [
                {'index': 0, 'id': callId, 'type': 'function', 'function': {'name': name, 'arguments': ''}},
              ],
            },
            'finish_reason': null,
          },
        ],
      }),
    ),
  );
  for (final delta in argDeltas) {
    buffer.write(
      _sse(
        json.encode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion.chunk',
          'created': 1,
          'model': 'gpt-4o-mini',
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {'index': 0, 'function': {'arguments': delta}},
                ],
              },
              'finish_reason': null,
            },
          ],
        }),
      ),
    );
  }
  buffer.write(
    _sse(
      json.encode({
        'id': 'chatcmpl-1',
        'object': 'chat.completion.chunk',
        'created': 1,
        'model': 'gpt-4o-mini',
        'choices': [
          {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'},
        ],
      }),
    ),
  );
  return buffer.toString();
}

void main() {
  group('OpenAI streaming live tool call metadata', () {
    test('emits a live_tool_call metadata chunk when the tool name is seen', () async {
      final model = _modelWithStream(_toolCallSse());

      final liveUpdates = <Map<String, String>>[];
      await for (final result in model.sendStream(
        [o.ChatMessage(role: o.MessageRole.user, content: 'search net')],
      )) {
        final live = result.metadata[kLiveToolCallMetadataKey];
        if (live is Map) {
          liveUpdates.add(
            live.map((k, v) => MapEntry(k as String, v as String)),
          );
        }
      }

      expect(liveUpdates, isNotEmpty);
      final first = liveUpdates.first;
      expect(first['id'], 'call_1');
      expect(first['name'], 'search');
    });

    test('grows the live args preview across delta chunks', () async {
      final model = _modelWithStream(_toolCallSse());

      final liveUpdates = <Map<String, String>>[];
      await for (final result in model.sendStream(
        [o.ChatMessage(role: o.MessageRole.user, content: 'search net')],
      )) {
        final live = result.metadata[kLiveToolCallMetadataKey];
        if (live is Map) {
          liveUpdates.add(
            live.map((k, v) => MapEntry(k as String, v as String)),
          );
        }
      }

      expect(liveUpdates.length, greaterThanOrEqualTo(3));
      expect(liveUpdates[0]['args'], '');
      expect(liveUpdates[1]['args'], '{"q": "te');
      expect(liveUpdates[2]['args'], '{"q": "test"}');
    });

    test('final message still exposes the complete tool call', () async {
      final model = _modelWithStream(_toolCallSse());

      final toolCallParts = <ToolPart>[];
      await for (final result in model.sendStream(
        [o.ChatMessage(role: o.MessageRole.user, content: 'search net')],
      )) {
        for (final message in result.messages) {
          toolCallParts.addAll(
            message.parts.whereType<ToolPart>().where(
              (p) => p.kind == ToolPartKind.call,
            ),
          );
        }
      }

      expect(toolCallParts, hasLength(1));
      expect(toolCallParts.single.name, 'search');
      expect(toolCallParts.single.arguments?['q'], 'test');
    });
  });
}