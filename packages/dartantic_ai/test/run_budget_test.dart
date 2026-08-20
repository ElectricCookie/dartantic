import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

void main() {
  group('RunBudgetTracker', () {
    test('active time excludes paused tool window', () async {
      final tracker = RunBudgetTracker(
        const AgentRunLimits(maxActiveDuration: Duration(seconds: 10)),
      );

      tracker.onIterationStart();
      tracker.onModelChunk();
      expect(tracker.activeElapsed, greaterThan(Duration.zero));

      tracker.onToolBatchStart();
      final elapsedAtPause = tracker.activeElapsed;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tracker.activeElapsed, elapsedAtPause);
    });

    test('throws when tool rounds exceeded', () {
      final tracker = RunBudgetTracker(const AgentRunLimits(maxToolRounds: 1));

      tracker.onToolBatchStart();
      expect(
        () => tracker.onToolBatchStart(),
        throwsA(isA<RunBudgetExceeded>()),
      );
    });

    test('throws when iterations exceeded', () {
      final tracker = RunBudgetTracker(const AgentRunLimits(maxIterations: 1));

      tracker.onIterationStart();
      expect(
        () => tracker.onIterationStart(),
        throwsA(isA<RunBudgetExceeded>()),
      );
    });

    test('throws when active time exceeded', () {
      final tracker = RunBudgetTracker(
        const AgentRunLimits(maxActiveDuration: Duration.zero),
      );

      tracker.onIterationStart();
      expect(
        () => tracker.onModelChunk(),
        throwsA(
          predicate<RunBudgetExceeded>(
            (e) => e.reason == RunBudgetExceededReason.activeTime,
          ),
        ),
      );
    });
  });
}
