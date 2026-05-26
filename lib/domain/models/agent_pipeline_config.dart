enum AgentPipelineMode {
  legacyPkm('legacy_pkm'),
  splitShadow('split_shadow'),
  splitPrimary('split_primary');

  const AgentPipelineMode(this.storageValue);

  final String storageValue;

  static AgentPipelineMode fromStorageValue(String? value) {
    for (final mode in AgentPipelineMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return AgentPipelineMode.legacyPkm;
  }
}

class AgentPipelineConfig {
  final AgentPipelineMode mode;

  const AgentPipelineConfig({this.mode = AgentPipelineMode.legacyPkm});

  bool get runsLegacyPkm =>
      mode == AgentPipelineMode.legacyPkm ||
      mode == AgentPipelineMode.splitShadow;

  bool get runsSplitPipeline =>
      mode == AgentPipelineMode.splitShadow ||
      mode == AgentPipelineMode.splitPrimary;

  bool get splitWritesPrimary => mode == AgentPipelineMode.splitPrimary;

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
