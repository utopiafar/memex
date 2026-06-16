import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/domain/models/embedding_config.dart';

void main() {
  group('EmbeddingService', () {
    tearDown(() {
      EmbeddingService.instance.httpPostOverride = null;
      EmbeddingService.instance.clearMemoryCacheForTesting();
    });

    test('calls OpenAI-compatible embeddings endpoint and caches result',
        () async {
      var calls = 0;
      Uri? capturedUri;
      Map<String, dynamic>? capturedBody;

      EmbeddingService.instance.httpPostOverride = (uri, headers, body) async {
        calls += 1;
        capturedUri = uri;
        capturedBody = jsonDecode(body as String) as Map<String, dynamic>;
        expect(headers['Authorization'], 'Bearer test-key');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'embedding': [1, 0, 0],
              }
            ],
          }),
          200,
        );
      };

      const config = EmbeddingConfig(
        enabled: true,
        apiKey: 'test-key',
        baseUrl: 'https://openrouter.ai/api/v1/',
        model: 'qwen/qwen3-embedding-8b',
      );

      final first = await EmbeddingService.instance
          .embedText('hello world', config: config);
      final second = await EmbeddingService.instance
          .embedText('hello world', config: config);

      expect(first, [1.0, 0.0, 0.0]);
      expect(second, [1.0, 0.0, 0.0]);
      expect(calls, 1);
      expect(capturedUri.toString(), 'https://openrouter.ai/api/v1/embeddings');
      expect(capturedBody, {
        'model': 'qwen/qwen3-embedding-8b',
        'input': 'hello world',
      });
    });

    test('cosineSimilarity returns null for mismatched dimensions', () {
      expect(
        EmbeddingService.instance.cosineSimilarity([1, 0], [1, 0, 0]),
        isNull,
      );
      expect(
        EmbeddingService.instance.cosineSimilarity([1, 0], [1, 0]),
        1.0,
      );
    });

    test('batches uncached texts and preserves result order', () async {
      final bodies = <Map<String, dynamic>>[];

      EmbeddingService.instance.httpPostOverride = (uri, headers, body) async {
        final decoded = jsonDecode(body as String) as Map<String, dynamic>;
        bodies.add(decoded);
        final rawInput = decoded['input'];
        final inputs = rawInput is List
            ? rawInput.cast<String>()
            : <String>[rawInput.toString()];
        return http.Response(
          jsonEncode({
            'data': [
              for (var i = 0; i < inputs.length; i++)
                {
                  'embedding': [i + 1, 0, 0],
                },
            ],
          }),
          200,
        );
      };

      const config = EmbeddingConfig(
        enabled: true,
        apiKey: 'test-key',
        baseUrl: 'https://openrouter.ai/api/v1/',
        model: 'qwen/qwen3-embedding-8b',
      );

      final first = await EmbeddingService.instance.embedTexts(
        ['alpha', 'beta', 'alpha'],
        config: config,
      );
      final second = await EmbeddingService.instance.embedTexts(
        ['beta', 'gamma'],
        config: config,
      );

      expect(first, [
        [1.0, 0.0, 0.0],
        [2.0, 0.0, 0.0],
        [1.0, 0.0, 0.0],
      ]);
      expect(second, [
        [2.0, 0.0, 0.0],
        [1.0, 0.0, 0.0],
      ]);
      expect(bodies, hasLength(2));
      expect(bodies.first['input'], ['alpha', 'beta']);
      expect(bodies.last['input'], 'gamma');
    });
  });
}
