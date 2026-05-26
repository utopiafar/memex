import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/agent_pipeline_config.dart';

void main() {
  test('defaults to legacy PKM', () {
    const config = AgentPipelineConfig();

    expect(config.mode, AgentPipelineMode.legacyPkm);
    expect(config.runsLegacyPkm, isTrue);
    expect(config.runsSplitPipeline, isFalse);
    expect(config.splitWritesPrimary, isFalse);
  });

  test('split shadow runs both chains without primary writes', () {
    const config = AgentPipelineConfig(mode: AgentPipelineMode.splitShadow);

    expect(config.runsLegacyPkm, isTrue);
    expect(config.runsSplitPipeline, isTrue);
    expect(config.splitWritesPrimary, isFalse);
  });

  test('split primary disables legacy PKM and writes primary insight', () {
    const config = AgentPipelineConfig(mode: AgentPipelineMode.splitPrimary);

    expect(config.runsLegacyPkm, isFalse);
    expect(config.runsSplitPipeline, isTrue);
    expect(config.splitWritesPrimary, isTrue);
  });
}
