import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:memex/data/services/embedding_service.dart';
import 'package:memex/domain/models/embedding_config.dart';

void main() {
  const config = EmbeddingConfig(
    enabled: true,
    baseUrl: 'https://openrouter.ai/api/v1/',
    apiKey: 'test-key',
    model: 'test-embed',
  );

  tearDown(() {
    EmbeddingService.instance.httpPostOverride = null;
    EmbeddingService.instance.clearMemoryCacheForTesting();
  });

  test('calls embeddings endpoint and parses vectors', () async {
    Uri? observedUri;
    Object? observedBody;
    Map<String, String>? observedHeaders;

    EmbeddingService.instance.httpPostOverride = (uri, headers, body) async {
      observedUri = uri;
      observedHeaders = headers;
      observedBody = body;
      return http.Response('{"data":[{"embedding":[1,0.5,-1]}]}', 200);
    };

    final vector = await EmbeddingService.instance.embedText(
      'hello',
      config: config,
    );

    expect(observedUri.toString(), 'https://openrouter.ai/api/v1/embeddings');
    expect(observedHeaders!['Authorization'], 'Bearer test-key');
    expect(observedBody.toString(), contains('"model":"test-embed"'));
    expect(vector, [1.0, 0.5, -1.0]);
  });

  test('uses in-memory cache for repeated text', () async {
    var calls = 0;
    EmbeddingService.instance.httpPostOverride = (_, __, ___) async {
      calls += 1;
      return http.Response('{"data":[{"embedding":[0.1,0.2]}]}', 200);
    };

    final first = await EmbeddingService.instance.embedText(
      'cached text',
      config: config,
    );
    final second = await EmbeddingService.instance.embedText(
      'cached text',
      config: config,
    );

    expect(first, second);
    expect(calls, 1);
  });

  test('computes cosine similarity', () {
    final similarity = EmbeddingService.instance.cosineSimilarity(
      [1, 0],
      [0.5, 0],
    );

    expect(similarity, closeTo(1.0, 0.0001));
  });
}
