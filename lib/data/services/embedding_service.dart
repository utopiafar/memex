import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:memex/domain/models/embedding_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

typedef EmbeddingHttpPost = Future<http.Response> Function(
  Uri uri,
  Map<String, String> headers,
  Object body,
);

class EmbeddingService {
  EmbeddingService._();

  static final EmbeddingService instance = EmbeddingService._();

  final Logger _logger = getLogger('EmbeddingService');
  final Map<String, List<double>> _memoryCache = {};

  EmbeddingHttpPost? httpPostOverride;

  Future<List<double>?> embedText(
    String text, {
    EmbeddingConfig? config,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final effectiveConfig = config ?? await UserStorage.getEmbeddingConfig();
    if (!effectiveConfig.isUsable) return null;

    final cacheKey = _cacheKey(trimmed, effectiveConfig.model);
    final cached = _memoryCache[cacheKey];
    if (cached != null) return cached;

    try {
      final uri = Uri.parse(
        '${_trimTrailingSlash(effectiveConfig.baseUrl)}/embeddings',
      );
      final headers = {
        'Authorization': 'Bearer ${effectiveConfig.apiKey}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'HTTP-Referer': 'https://memex.local',
        'X-Title': 'Memex',
      };
      final body = jsonEncode({
        'model': effectiveConfig.model,
        'input': trimmed,
      });
      final post = httpPostOverride ??
          (Uri uri, Map<String, String> headers, Object body) {
            return http.post(uri, headers: headers, body: body);
          };

      final response = await post(
        uri,
        headers,
        body,
      ).timeout(Duration(seconds: effectiveConfig.timeoutSeconds));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logger.warning(
          'Embedding request failed: status=${response.statusCode}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      final embedding = _parseEmbedding(decoded);
      if (embedding == null || embedding.isEmpty) return null;

      if (_memoryCache.length > 512) {
        _memoryCache.remove(_memoryCache.keys.first);
      }
      _memoryCache[cacheKey] = embedding;
      return embedding;
    } catch (e) {
      _logger.warning('Embedding request failed: $e');
      return null;
    }
  }

  double? cosineSimilarity(List<double>? a, List<double>? b) {
    if (a == null || b == null || a.isEmpty || a.length != b.length) {
      return null;
    }
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return null;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  void clearMemoryCacheForTesting() {
    _memoryCache.clear();
  }

  List<double>? _parseEmbedding(dynamic decoded) {
    if (decoded is! Map) return null;
    final data = decoded['data'];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map) {
        return _numberList(first['embedding']);
      }
    }
    return _numberList(decoded['embedding']);
  }

  List<double>? _numberList(dynamic raw) {
    if (raw is! List) return null;
    final values = <double>[];
    for (final item in raw) {
      if (item is num) {
        values.add(item.toDouble());
      } else {
        return null;
      }
    }
    return values;
  }

  String _cacheKey(String text, String model) {
    final digest = sha256.convert(utf8.encode('$model\n$text')).toString();
    return digest;
  }

  String _trimTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
