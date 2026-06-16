import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/embedding_config.dart';

void main() {
  group('EmbeddingConfig', () {
    test('default config is disabled but points to the lightweight first model',
        () {
      const config = EmbeddingConfig();

      expect(config.enabled, isFalse);
      expect(config.baseUrl, 'https://openrouter.ai/api/v1');
      expect(config.model, 'qwen/qwen3-embedding-8b');
      expect(config.isUsable, isFalse);
    });

    test('usable only when enabled and credentials are present', () {
      const config = EmbeddingConfig(
        enabled: true,
        apiKey: 'test-key',
      );

      expect(config.isUsable, isTrue);
    });

    test('round trips through json', () {
      const config = EmbeddingConfig(
        enabled: true,
        baseUrl: 'https://example.test/v1',
        apiKey: 'key',
        model: 'model-a',
        timeoutSeconds: 9,
      );

      expect(
          EmbeddingConfig.fromJson(config.toJson()).toJson(), config.toJson());
    });
  });
}
