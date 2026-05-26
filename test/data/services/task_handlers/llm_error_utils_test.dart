import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/task_handlers/llm_error_utils.dart';
import 'package:memex/domain/models/task_exceptions.dart';

void main() {
  test('treats prematurely closed HTTP 400 as retryable transport error', () {
    final error = Exception(
      'AgentException(code: llmError, error: HTTP 400: Request failed, '
      'param: Connection prematurely closed BEFORE response)',
    );

    expect(classifyError(error), LlmErrorCategory.networkError);
    expect(
      () => rethrowIfNonRetryable(error),
      throwsA(predicate<Object>((e) => identical(e, error))),
    );
  });

  test('keeps genuine HTTP 400 errors non-retryable', () {
    final error = Exception('HTTP 400: invalid request schema');

    expect(classifyError(error), LlmErrorCategory.badRequest);
    expect(
      () => rethrowIfNonRetryable(error),
      throwsA(isA<NonRetryableLlmException>()),
    );
  });
}
