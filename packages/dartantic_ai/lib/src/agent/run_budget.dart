/// Limits for a single [Agent.sendStream] run.
class AgentRunLimits {
  const AgentRunLimits({
    this.maxActiveDuration,
    this.maxToolRounds,
    this.maxIterations,
  });

  /// Maximum active model-streaming time (excludes tool execution and approval
  /// waits, which run while the budget is paused).
  final Duration? maxActiveDuration;

  /// Maximum tool-call batches per sendStream (one batch per model tool round).
  final int? maxToolRounds;

  /// Maximum orchestrator loop trips (model → tools → model).
  final int? maxIterations;
}

enum RunBudgetExceededReason { activeTime, toolRounds, iterations }

/// Thrown when an [AgentRunLimits] cap is exceeded during streaming.
class RunBudgetExceeded implements Exception {
  const RunBudgetExceeded(this.reason);

  final RunBudgetExceededReason reason;

  @override
  String toString() => 'RunBudgetExceeded($reason)';
}

/// Tracks active model time and counts for a single sendStream run.
class RunBudgetTracker {
  RunBudgetTracker(this.limits);

  final AgentRunLimits limits;

  Duration _accumulatedActive = Duration.zero;
  Stopwatch? _activeStopwatch;
  int iterationCount = 0;
  int toolRoundCount = 0;

  Duration get activeElapsed {
    if (_activeStopwatch != null && _activeStopwatch!.isRunning) {
      return _accumulatedActive + _activeStopwatch!.elapsed;
    }
    return _accumulatedActive;
  }

  void resumeActive() {
    _activeStopwatch ??= Stopwatch()..start();
    if (!_activeStopwatch!.isRunning) {
      _activeStopwatch!.start();
    }
  }

  void pauseActive() {
    final stopwatch = _activeStopwatch;
    if (stopwatch == null || !stopwatch.isRunning) {
      return;
    }
    stopwatch.stop();
    _accumulatedActive += stopwatch.elapsed;
    stopwatch.reset();
  }

  void onIterationStart() {
    iterationCount++;
    final maxIterations = limits.maxIterations;
    if (maxIterations != null && iterationCount > maxIterations) {
      throw const RunBudgetExceeded(RunBudgetExceededReason.iterations);
    }
    resumeActive();
  }

  void onModelChunk() {
    resumeActive();
    _checkActiveTime();
  }

  void onToolBatchStart() {
    pauseActive();
    toolRoundCount++;
    final maxToolRounds = limits.maxToolRounds;
    if (maxToolRounds != null && toolRoundCount > maxToolRounds) {
      throw const RunBudgetExceeded(RunBudgetExceededReason.toolRounds);
    }
  }

  void _checkActiveTime() {
    final maxActive = limits.maxActiveDuration;
    if (maxActive != null && activeElapsed > maxActive) {
      throw const RunBudgetExceeded(RunBudgetExceededReason.activeTime);
    }
  }
}
