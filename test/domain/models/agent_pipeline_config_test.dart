import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/agent_pipeline_config.dart';

void main() {
  group('AgentPipelineConfig', () {
    test('defaults to legacy PKM', () {
      const config = AgentPipelineConfig();

      expect(config.mode, AgentPipelineMode.legacyPkm);
      expect(config.runsLegacyPkm, isTrue);
      expect(config.runsMemoryPrimary, isFalse);
    });

    test('parses memory primary mode from storage', () {
      final config = AgentPipelineConfig.fromJson(
        const {'mode': 'memory_primary'},
      );

      expect(config.mode, AgentPipelineMode.memoryPrimary);
      expect(config.runsLegacyPkm, isFalse);
      expect(config.runsMemoryPrimary, isTrue);
    });

    test('unknown mode falls back to legacy', () {
      expect(
        AgentPipelineMode.fromStorageValue('split_shadow'),
        AgentPipelineMode.legacyPkm,
      );
    });
  });
}
