import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/embedding_config.dart';

void main() {
  test('default embedding config is disabled and not usable', () {
    const config = EmbeddingConfig();

    expect(config.enabled, isFalse);
    expect(config.model, 'perplexity/pplx-embed-v1-4b');
    expect(config.isUsable, isFalse);
  });

  test('usable only when enabled and all endpoint fields are present', () {
    const disabled = EmbeddingConfig(
      enabled: false,
      baseUrl: 'https://openrouter.ai/api/v1',
      apiKey: 'key',
      model: 'model',
    );
    final enabled = disabled.copyWith(enabled: true);

    expect(disabled.isUsable, isFalse);
    expect(enabled.isUsable, isTrue);
    expect(enabled.copyWith(apiKey: '').isUsable, isFalse);
  });

  test('round-trips json fields', () {
    const config = EmbeddingConfig(
      enabled: true,
      baseUrl: 'https://example.com/v1',
      apiKey: 'secret',
      model: 'embed-model',
      timeoutSeconds: 12,
    );

    final restored = EmbeddingConfig.fromJson(config.toJson());

    expect(restored.enabled, isTrue);
    expect(restored.baseUrl, 'https://example.com/v1');
    expect(restored.apiKey, 'secret');
    expect(restored.model, 'embed-model');
    expect(restored.timeoutSeconds, 12);
  });
}
