enum AgentPipelineMode {
  legacyPkm('legacy_pkm'),
  memoryPrimary('memory_primary');

  const AgentPipelineMode(this.storageValue);

  final String storageValue;

  static AgentPipelineMode fromStorageValue(String? value) {
    final normalized = value?.trim();
    for (final mode in AgentPipelineMode.values) {
      if (mode.storageValue == normalized) return mode;
    }
    return AgentPipelineMode.legacyPkm;
  }
}

class AgentPipelineConfig {
  final AgentPipelineMode mode;

  const AgentPipelineConfig({this.mode = AgentPipelineMode.legacyPkm});

  bool get runsLegacyPkm => mode == AgentPipelineMode.legacyPkm;

  bool get runsMemoryPrimary => mode == AgentPipelineMode.memoryPrimary;

  Map<String, dynamic> toJson() {
    return {'mode': mode.storageValue};
  }

  factory AgentPipelineConfig.fromJson(Map<String, dynamic> json) {
    return AgentPipelineConfig(
      mode: AgentPipelineMode.fromStorageValue(json['mode'] as String?),
    );
  }

  AgentPipelineConfig copyWith({AgentPipelineMode? mode}) {
    return AgentPipelineConfig(mode: mode ?? this.mode);
  }
}
