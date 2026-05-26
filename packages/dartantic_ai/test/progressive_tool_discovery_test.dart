import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_tools.dart';

class MockToolSource implements ProgressiveToolSource {
  @override
  Future<List<ProgressiveToolDescriptor>> searchTools(String query) async {
    if (query.toLowerCase().contains('weather')) {
      return [
        const ProgressiveToolDescriptor(
          name: 'get_weather',
          description: 'Get the current weather for a city',
        ),
      ];
    }
    return [];
  }

  @override
  Future<Tool> getTool(String name) async {
    if (name == 'get_weather') return weatherTool;
    throw Exception('Tool $name not found');
  }
}

void main() {
  group('Progressive Tool Discovery', () {
    late MockToolSource toolSource;

    setUp(() {
      toolSource = MockToolSource();
    });

    group('Agent', () {
      test('addTool makes tool available to the agent', () async {
        final agent = Agent('ollama:llama2');
        agent.addTool(weatherTool);
        expect(agent.model, contains('ollama'));
      });

      test('Agent with toolSource auto-registers discovery tools', () async {
        final agent = Agent('ollama:llama2', toolSource: toolSource);
        expect(agent.model, contains('ollama'));
      });

      test('multiple addTool calls work correctly', () async {
        final agent = Agent('ollama:llama2');
        agent.addTool(weatherTool);
        agent.addTool(Tool<Map<String, dynamic>>(
          name: 'test_tool',
          description: 'A test tool',
          inputSchema: JsonSchema.create({'type': 'object', 'properties': {}}),
          onCall: (args) async => 'test result',
        ));
        expect(agent.model, contains('ollama'));
      });

      test('removeTool removes tool from agent', () async {
        final agent = Agent('ollama:llama2');
        agent.addTool(weatherTool);
        agent.removeTool('get_weather');
        expect(agent.model, contains('ollama'));
      });

      test('Agent.forProvider with toolSource auto-registers discovery tools',
          () async {
        final provider = Agent.getProvider('ollama');
        final agent = Agent.forProvider(
          provider,
          toolSource: toolSource,
        );
        expect(agent.model, contains('ollama'));
      });
    });

    group('StreamingState', () {
      test('rebuildToolMap updates tool map in-place', () {
        final state = StreamingState(
          conversationHistory: [],
          toolMap: {'existing_tool': weatherTool},
        );

        final newTool = Tool<Map<String, dynamic>>(
          name: 'new_tool',
          description: 'A new tool',
          inputSchema: JsonSchema.create({'type': 'object', 'properties': {}}),
          onCall: (args) async => 'result',
        );

        state.rebuildToolMap([newTool]);

        expect(state.toolMap, contains('new_tool'));
        expect(state.toolMap, isNot(contains('existing_tool')));
        expect(state.toolMap.length, equals(1));
      });

      test('rebuildToolMap with empty list clears tool map', () {
        final state = StreamingState(
          conversationHistory: [],
          toolMap: {'tool1': weatherTool},
        );

        state.rebuildToolMap([]);

        expect(state.toolMap, isEmpty);
      });
    });

    group('ProgressiveToolSource', () {
      test('searchTools returns matching descriptors', () async {
        final results = await toolSource.searchTools('weather');
        expect(results, hasLength(1));
        expect(results.first.name, equals('get_weather'));
      });

      test('searchTools returns empty for non-matching query', () async {
        final results = await toolSource.searchTools('nonexistent');
        expect(results, isEmpty);
      });

      test('getTool returns full tool by name', () async {
        final tool = await toolSource.getTool('get_weather');
        expect(tool.name, equals('get_weather'));
      });

      test('getTool throws for unknown tool', () async {
        expect(
          () => toolSource.getTool('unknown'),
          throwsException,
        );
      });
    });

    group('ProgressiveToolDescriptor', () {
      test('creates descriptor with name and description', () {
        const descriptor = ProgressiveToolDescriptor(
          name: 'test_tool',
          description: 'A test tool description',
        );
        expect(descriptor.name, equals('test_tool'));
        expect(descriptor.description, equals('A test tool description'));
      });
    });
  });
}
