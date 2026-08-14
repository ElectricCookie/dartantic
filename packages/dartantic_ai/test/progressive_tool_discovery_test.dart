import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_tools.dart';

class MockToolSource implements ProgressiveToolSource {
  @override
  Future<List<ProgressiveToolDescriptor>> searchTools(String query) async {
    final q = query.toLowerCase();
    final results = <ProgressiveToolDescriptor>[];
    if (q.contains('weather')) {
      results.add(
        const ProgressiveToolDescriptor(
          name: 'get_weather',
          description: 'Get the current weather for a city',
        ),
      );
    }
    if (q.contains('string')) {
      results.add(
        const ProgressiveToolDescriptor(
          name: 'string_tool',
          description: 'Returns a simple string',
        ),
      );
    }
    return results;
  }

  @override
  Future<Tool> getTool(String name) async {
    return switch (name) {
      'get_weather' => weatherTool,
      'string_tool' => stringTool,
      _ => throw Exception('Tool $name not found'),
    };
  }
}

Tool _discoveryTool(Agent agent, String name) =>
    agent.tools.firstWhere((t) => t.name == name);

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
        expect(
          agent.tools.map((t) => t.name),
          containsAll(['searchTools', 'useTool']),
        );
        expect(agent.tools.map((t) => t.name), isNot(contains('getToolDetail')));
      });

      test('useTool registers tools and returns schemas', () async {
        final agent = Agent('ollama:llama2', toolSource: toolSource);
        final useTool = _discoveryTool(agent, 'useTool');

        final result = await useTool.call({
          'names': ['get_weather', 'string_tool'],
        }) as Map<String, dynamic>;

        final tools = result['tools'] as List<dynamic>;
        expect(tools, hasLength(2));
        expect(tools[0]['name'], 'get_weather');
        expect(tools[0]['status'], 'registered');
        expect(tools[0]['inputSchema'], isA<Map>());
        expect(tools[1]['name'], 'string_tool');
        expect(tools[1]['status'], 'registered');
        expect(result.containsKey('errors'), isFalse);

        expect(
          agent.tools.map((t) => t.name),
          containsAll(['get_weather', 'string_tool']),
        );
      });

      test('useTool accepts legacy singular name', () async {
        final agent = Agent('ollama:llama2', toolSource: toolSource);
        final useTool = _discoveryTool(agent, 'useTool');

        final result = await useTool.call({'name': 'get_weather'})
            as Map<String, dynamic>;

        expect((result['tools'] as List).single['status'], 'registered');
        expect(agent.tools.map((t) => t.name), contains('get_weather'));
      });

      test('useTool reports already_registered and missing tools', () async {
        final agent = Agent('ollama:llama2', toolSource: toolSource);
        final useTool = _discoveryTool(agent, 'useTool');

        await useTool.call({
          'names': ['get_weather'],
        });
        final result = await useTool.call({
          'names': ['get_weather', 'missing_tool'],
        }) as Map<String, dynamic>;

        final tools = result['tools'] as List<dynamic>;
        expect(tools, hasLength(1));
        expect(tools.single['status'], 'already_registered');

        final errors = result['errors'] as List<dynamic>;
        expect(errors, hasLength(1));
        expect(errors.single['name'], 'missing_tool');
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

      test('addTool ignores duplicate tool names', () {
        final agent = Agent('ollama:llama2');
        agent.addTool(weatherTool);
        agent.addTool(weatherTool);
        agent.removeTool('get_weather');
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
