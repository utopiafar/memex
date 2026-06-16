class EmbeddingConfig {
  final bool enabled;
  final String baseUrl;
  final String apiKey;
  final String model;
  final int timeoutSeconds;

  const EmbeddingConfig({
    this.enabled = false,
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.apiKey = '',
    this.model = 'qwen/qwen3-embedding-8b',
    this.timeoutSeconds = 30,
  });

  bool get isUsable =>
      enabled &&
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'timeoutSeconds': timeoutSeconds,
    };
  }

  factory EmbeddingConfig.fromJson(Map<String, dynamic> json) {
    return EmbeddingConfig(
      enabled: json['enabled'] as bool? ?? false,
      baseUrl: json['baseUrl'] as String? ?? 'https://openrouter.ai/api/v1',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? 'qwen/qwen3-embedding-8b',
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 30,
    );
  }

  EmbeddingConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? timeoutSeconds,
  }) {
    return EmbeddingConfig(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }
}
