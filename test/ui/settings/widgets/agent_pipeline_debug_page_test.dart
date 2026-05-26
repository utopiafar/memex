import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/agent_pipeline_config.dart';
import 'package:memex/ui/settings/widgets/agent_pipeline_debug_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves pipeline mode and embedding configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AgentPipelineDebugPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('agent_pipeline_mode_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split Primary').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('embedding_enabled_switch')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('embedding_base_url_field')),
      'https://openrouter.ai/api/v1',
    );
    await tester.enterText(
      find.byKey(const Key('embedding_model_field')),
      'perplexity/pplx-embed-v1-4b',
    );
    await tester.enterText(
      find.byKey(const Key('embedding_api_key_field')),
      'test-key',
    );
    await tester.enterText(
      find.byKey(const Key('embedding_timeout_field')),
      '45',
    );

    await tester.tap(find.byKey(const Key('agent_pipeline_save_button')));
    await tester.pumpAndSettle();

    final pipeline = await UserStorage.getAgentPipelineConfig();
    final embedding = await UserStorage.getEmbeddingConfig();

    expect(pipeline.mode, AgentPipelineMode.splitPrimary);
    expect(embedding.enabled, isTrue);
    expect(embedding.baseUrl, 'https://openrouter.ai/api/v1');
    expect(embedding.model, 'perplexity/pplx-embed-v1-4b');
    expect(embedding.apiKey, 'test-key');
    expect(embedding.timeoutSeconds, 45);
  });
}
