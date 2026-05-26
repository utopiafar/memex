import 'package:flutter/material.dart';
import 'package:memex/domain/models/agent_pipeline_config.dart';
import 'package:memex/domain/models/embedding_config.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

class AgentPipelineDebugPage extends StatefulWidget {
  const AgentPipelineDebugPage({super.key});

  @override
  State<AgentPipelineDebugPage> createState() => _AgentPipelineDebugPageState();
}

class _AgentPipelineDebugPageState extends State<AgentPipelineDebugPage> {
  AgentPipelineMode _mode = AgentPipelineMode.legacyPkm;
  bool _embeddingEnabled = false;
  bool _obscureKey = true;
  bool _loading = true;
  bool _saving = false;

  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _timeoutController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pipeline = await UserStorage.getAgentPipelineConfig();
    final embedding = await UserStorage.getEmbeddingConfig();
    if (!mounted) return;
    setState(() {
      _mode = pipeline.mode;
      _embeddingEnabled = embedding.enabled;
      _baseUrlController.text = embedding.baseUrl;
      _modelController.text = embedding.model;
      _apiKeyController.text = embedding.apiKey;
      _timeoutController.text = embedding.timeoutSeconds.toString();
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await UserStorage.saveAgentPipelineConfig(
        AgentPipelineConfig(mode: _mode),
      );
      await UserStorage.saveEmbeddingConfig(
        EmbeddingConfig(
          enabled: _embeddingEnabled,
          baseUrl: _baseUrlController.text.trim(),
          model: _modelController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
          timeoutSeconds: int.tryParse(_timeoutController.text.trim()) ?? 30,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Pipeline'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: const Color(0xFFF7F8FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _section(
                  children: [
                    DropdownButtonFormField<AgentPipelineMode>(
                      key: const Key('agent_pipeline_mode_dropdown'),
                      initialValue: _mode,
                      decoration: const InputDecoration(
                        labelText: 'Pipeline',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: AgentPipelineMode.legacyPkm,
                          child: Text('Legacy PKM'),
                        ),
                        DropdownMenuItem(
                          value: AgentPipelineMode.splitShadow,
                          child: Text('Legacy + Split Shadow'),
                        ),
                        DropdownMenuItem(
                          value: AgentPipelineMode.splitPrimary,
                          child: Text('Split Primary'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _mode = value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _section(
                  children: [
                    SwitchListTile(
                      key: const Key('embedding_enabled_switch'),
                      value: _embeddingEnabled,
                      onChanged: (value) {
                        setState(() => _embeddingEnabled = value);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Embedding'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('embedding_base_url_field'),
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('embedding_model_field'),
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('embedding_api_key_field'),
                      controller: _apiKeyController,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() => _obscureKey = !_obscureKey);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('embedding_timeout_field'),
                      controller: _timeoutController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Timeout seconds',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('agent_pipeline_save_button'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            ),
    );
  }

  Widget _section({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE6E8EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
