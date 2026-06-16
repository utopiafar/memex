import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
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

  final _logger = getLogger('EmbeddingService');
  final Map<String, List<double>> _memoryCache = {};

  EmbeddingHttpPost? httpPostOverride;

  Future<List<double>?> embedText(
    String text, {
    EmbeddingConfig? config,
  }) async {
    final embeddings = await embedTexts([text], config: config);
    return embeddings.isEmpty ? null : embeddings.first;
  }

  Future<List<List<double>?>> embedTexts(
    List<String> texts, {
    EmbeddingConfig? config,
  }) async {
    if (texts.isEmpty) return const [];
    final effectiveConfig = config ?? await UserStorage.getEmbeddingConfig();
    if (!effectiveConfig.isUsable) {
      return List<List<double>?>.filled(texts.length, null);
    }

    final results = List<List<double>?>.filled(texts.length, null);
    final positionsByCacheKey = <String, List<int>>{};
    final uncachedTextsByKey = <String, String>{};

    for (var i = 0; i < texts.length; i++) {
      final trimmed = texts[i].trim();
      if (trimmed.isEmpty) continue;
      final cacheKey = _cacheKey(trimmed, effectiveConfig);
      final cached = _memoryCache[cacheKey];
      if (cached != null) {
        results[i] = cached;
        continue;
      }
      positionsByCacheKey.putIfAbsent(cacheKey, () => []).add(i);
      uncachedTextsByKey[cacheKey] = trimmed;
    }

    if (uncachedTextsByKey.isEmpty) return results;

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
      final uncachedKeys = uncachedTextsByKey.keys.toList(growable: false);
      final uncachedTexts = [
        for (final key in uncachedKeys) uncachedTextsByKey[key]!,
      ];
      final body = jsonEncode({
        'model': effectiveConfig.model,
        'input':
            uncachedTexts.length == 1 ? uncachedTexts.single : uncachedTexts,
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
        return results;
      }

      final decoded = jsonDecode(response.body);
      final embeddings = _parseEmbeddings(decoded);
      if (embeddings.length != uncachedTexts.length) return results;

      for (var i = 0; i < uncachedKeys.length; i++) {
        final embedding = embeddings[i];
        if (embedding == null || embedding.isEmpty) continue;
        final cacheKey = uncachedKeys[i];
        if (_memoryCache.length > 512) {
          _memoryCache.remove(_memoryCache.keys.first);
        }
        _memoryCache[cacheKey] = embedding;
        for (final position in positionsByCacheKey[cacheKey] ?? const <int>[]) {
          results[position] = embedding;
        }
      }
      return results;
    } catch (e) {
      _logger.warning('Embedding request failed: $e');
      return results;
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

  List<List<double>?> _parseEmbeddings(dynamic decoded) {
    if (decoded is! Map) return const [];
    final data = decoded['data'];
    if (data is List) {
      return [
        for (final item in data)
          if (item is Map) _numberList(item['embedding']) else null,
      ];
    }
    return [_numberList(decoded['embedding'])];
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

  String _cacheKey(String text, EmbeddingConfig config) {
    final digest = sha256
        .convert(utf8.encode('${config.baseUrl}\n${config.model}\n$text'))
        .toString();
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
