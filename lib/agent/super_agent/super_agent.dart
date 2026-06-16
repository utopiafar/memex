import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/agent_system_prompt_helper.dart';
import 'package:memex/agent/agent_controller.util.dart';
import 'package:memex/agent/built_in_tools/file_tools.dart';
import 'package:memex/agent/built_in_tools/search_event_logs_tool.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/agent/skills/manage_pkm/pkm_skill.dart';
import 'package:memex/agent/security/file_permission_manager.dart';
import 'package:memex/agent/skills/manage_timeline_card/timeline_card_skill.dart';
import 'package:memex/agent/skills/manage_system_action/system_action_skill.dart';
import 'package:memex/agent/skills/knowledge_insight/knowledge_insight_skill.dart';
import 'package:memex/agent/skills/ask_clarification/ask_clarification_skill.dart';
import 'package:memex/agent/common_tools.dart';
import 'package:memex/agent/state_util.dart';
import 'package:memex/agent/super_agent/prompts.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:logging/logging.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// Read-only tool names available in Quick Query mode.
const _readOnlyToolNames = {
  'LS',
  'Glob',
  'Grep',
  'Read',
  'BatchRead',
  'search_event_logs',
  'search_workspace_event_logs',
  'search_memory_primary',
  'getCurrentTime',
  'get_pkm_overview',
};

const _memoryPrimaryQuickQueryToolNames = {
  'search_memory_primary',
  'getCurrentTime',
};

/// Skills excluded in Quick Query mode (those that create/modify data).
const _quickQueryExcludedSkills = {
  'manage_timeline_card',
  'ask_clarification',
};

class SuperAgent {
  static final Logger _logger = getLogger('SuperAgent');

  /// Whether this agent operates in read-only Quick Query mode.
  static Future<StatefulAgent> createAgent(
      {required LLMClient client,
      required ModelConfig modelConfig,
      required String userId,
      required String name,
      required AgentState state,
      AgentController? controller,
      List<String>? forceActiveSkills,
      bool disableSubAgents = false,
      bool quickQuery = false,
      String? additionalSystemPrompt}) async {
    final fileService = FileSystemService.instance;
    final pipelineConfig = await UserStorage.getAgentPipelineConfig();
    final useMemoryPrimary = pipelineConfig.runsMemoryPrimary;

    controller = controller ?? AgentController();
    addAgentLogger(controller);
    addAgentActivityCollector(controller);

    final workingDirectory = fileService.getWorkspacePath(userId);

    // SuperAgent has full access to the workspace (read-only in Quick Query)
    final permissionManager = FilePermissionManager(userId, [
      PermissionRule(
          rootPath: fileService.getWorkspacePath(userId),
          access: quickQuery ? FileAccessType.read : FileAccessType.write),
    ]);

    final fileToolFactory = FileToolFactory(
      permissionManager: permissionManager,
      workingDirectory: workingDirectory,
    );

    final allTools = [
      fileToolFactory.buildLSTool(),
      fileToolFactory.buildGlobTool(),
      fileToolFactory.buildGrepTool(),
      fileToolFactory.buildReadTool(),
      fileToolFactory.buildBatchReadTool(),
      fileToolFactory.buildWriteTool(),
      fileToolFactory.buildMoveTool(),
      fileToolFactory.buildRemoveTool(),
      fileToolFactory.buildEditTool(),
      buildSearchEventLogsTool(),
      if (useMemoryPrimary) buildSearchMemoryPrimaryTool(),
      getCurrentTimeTool,
      getPkmOverviewTool
    ];

    // Filter tools in Quick Query mode — only keep read-only tools
    final quickQueryToolNames = useMemoryPrimary
        ? _memoryPrimaryQuickQueryToolNames
        : _readOnlyToolNames;
    final tools = quickQuery
        ? allTools.where((t) => quickQueryToolNames.contains(t.name)).toList()
        : allTools;

    // Memory Management (skip write tools in Quick Query mode)
    final memoryManagement = await MemoryManagement.createDefault(
      userId: userId,
      sourceAgent: name,
    );
    final memorySystemPrompt = quickQuery
        ? await memoryManagement.buildMemoryReadOnlyPrompt()
        : await memoryManagement.buildSuperAgentMemoryManagementPrompt();
    if (!quickQuery) {
      final memoryManagementTools =
          memoryManagement.buildMemoryManagementTools();
      tools.addAll(memoryManagementTools);
    }

    final userMemory = await memoryManagement.buildMemoryPrompt();
    state.systemReminders["user_memory"] = userMemory;

    var skills = [
      KnowledgeInsightSkill(),
      TimelineCardSkill(),
      PkmSkill(workingDirectory: '/PKM'),
      SystemActionSkill(),
      AskClarificationSkill(),
    ];
    if (quickQuery) {
      skills = skills
          .where((s) => !_quickQueryExcludedSkills.contains(s.name))
          .toList();
    }
    if (forceActiveSkills != null) {
      for (var skill in skills) {
        if (forceActiveSkills.contains(skill.name)) {
          skill.forceActivate = true;
        }
      }
    }

    final systemPrompts = [superAgentSystemPrompt, memorySystemPrompt];
    if (quickQuery) {
      systemPrompts.add(
        '## Quick Query Mode\n'
        'You are in **Quick Query** (read-only) mode. You can ONLY read and search existing data.\n'
        'You MUST NOT create, modify, or delete any records, cards, knowledge entries, or files.\n'
        'When answering a project-specific question, preserve and repeat the project/entity name exactly as the user wrote it in the question.\n'
        'Do not rely on file names alone for personal knowledge questions. If you use PKM tools, search file contents with `Grep` or read relevant files after `get_pkm_overview`.\n'
        'If the user asks you to create or change something, explain that this is a read-only mode '
        'and suggest they use the full Chat mode instead.',
      );
      if (useMemoryPrimary) {
        systemPrompts.add(
          '## Memory Primary Recall\n'
          'When the user asks about their preferences, remembered facts, project state, decisions, corrections, relationships, or prior context, use `search_memory_primary` as the primary and only personal-knowledge recall tool. Do not fall back to PKM, Grep, Read, or file browsing for these questions in Memory Primary mode.\n'
          'Prefer one call with the original user question and `limit: 10`. For multi-part relationship questions, use at most two focused follow-up calls containing the concrete responsibility words from the user question, such as 产品评审, 体验文案, 合同付款, or 发票确认.\n'
          'If the chat already includes a preloaded `<memory_primary_context>` reminder, answer from that context and avoid additional tool calls unless the context is clearly insufficient.\n'
          'If Memory Primary returns relevant memories, ground the answer in those memories and cite their evidence fact ids when useful.\n'
          'Answer only the fields the user asked for. Do not fill report-template fields with project owner, risk, next-step, benefit, OCR, or failure-recovery details unless the user explicitly asks for those details and the returned Memory Primary context directly supports them.\n'
          'When answering current-state questions with corrected or superseded facts, state only the current value. Do not name stale values or quote stale clauses; say "previous records were superseded" unless the user explicitly asks for history.\n'
          'For owner/current-state questions, do not say there is "no extra risk" or prescribe a next step unless a returned memory explicitly says so. If risk evidence was not retrieved, omit the risk field.\n'
          'If you inspect raw Facts, Cards, PKM, or projection files for evidence on a current-state question, cite the evidence fact id/date and paraphrase only the current-value clause. Never copy a correction sentence that contains a stale value.\n'
          'For preference questions, preserve all explicit preference constraints returned by Memory Primary, including original user wording such as latest conclusion, conclusion-first, risk-first, owner, deadline, evidence source, background placement, or impact scope. If `search_memory_primary` returns a `<preference_constraints>` block, include every bullet from it in the final answer as format requirements, not as filled-in project facts.\n',
        );
      }
    }
    if (additionalSystemPrompt != null) {
      systemPrompts.add(additionalSystemPrompt);
    }

    final agent = StatefulAgent(
        name: name,
        client: client,
        modelConfig: modelConfig,
        state: state,
        compressor: LLMBasedContextCompressor(
          client: client,
          modelConfig: modelConfig,
          totalTokenThreshold: 64000,
          keepRecentMessageSize: 10,
        ),
        tools: tools,
        skills: skills,
        systemPrompts: systemPrompts,
        disableSubAgents: true,
        controller: controller,
        withGeneralPrinciples: true,
        planMode:
            quickQuery && useMemoryPrimary ? PlanMode.none : PlanMode.auto,
        autoSaveStateFunc: (state) async {
          await saveAgentState(state);
        },
        systemCallback: createSystemCallback(userId));

    _logger.info(
        'SuperAgent created, userId: $userId, sessionId: ${state.sessionId}');
    return agent;
  }
}
