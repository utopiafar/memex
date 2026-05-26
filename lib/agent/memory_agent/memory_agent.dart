import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/agent/agent_system_prompt_helper.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/memory/memory_management.dart';
import 'package:memex/agent/skills/ask_clarification/ask_clarification_skill.dart';
import 'package:memex/agent/state_util.dart';
import 'package:memex/agent/agent_controller.util.dart';

class MemoryAgent {
  static final Logger _logger = Logger('MemoryAgent');

  static Future<void> run({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String bufferedContent,
  }) async {
    final memoryManagement = await MemoryManagement.createDefault(
      userId: userId,
      sourceAgent: 'memory_agent',
    );

    // Create a new session for this analysis
    final sessionId =
        'memory_analysis_${DateTime.now().millisecondsSinceEpoch}';

    // Load existing memory context so the agent knows what's already recorded
    final existingMemory = await memoryManagement.buildMemoryPrompt();

    const systemPrompt = '''# Role
You are a **Strict Memory Curator**.
Your job is to **FILTER OUT** noise and only persist **high-value, permanent user attributes**.

# 🛑 CRITICAL RULE: The "Default Deny" Policy
**Most user inputs are temporary noise. Do NOT record them.**
You should only call `append_memories` if you find information that is **vital for months or years to come**.
If a batch contains only casual chat, tasks, or temporary context, **DO NOT call any tools. Just stop.**

# 🗑️ EXCLUSION LIST (What to IGNORE)
**Do NOT create memories for:**
1.  **One-off Tasks & Reminders**: "Remind me to cancel the 29 RMB plan", "Buy milk", "Fix this bug". (These are isolated To-Dos, not User Traits).
2.  **Transient Context**: "Where is the nearest gas station?", "The weather is hot", "I'm hungry".
3.  **One-off Actions**: "I just bought a coffee", "I am testing this code".
4.  **Already Known Info**: Facts already present in `<existing_memory_context>`, unless the new evidence explicitly confirms, corrects, or refreshes the source for the current truth.

# 💎 INCLUSION LIST (What to KEEP)
**Only record PERMANENT attributes:**
1.  **User Identity**: "I am a Python developer", "I have two daughters".
2.  **Strong Preferences**: "I hate cilantro", "I only use Linux".
3.  **Long-term Assets/Environment**: "I use a MacBook Pro M3", "My home has floor heating".
4.  **Recurring Habits**: "I run 5km every morning" (Pattern), NOT "I ran today" (Event).
5.  **AI Interaction Preferences**: "Ask me fewer clarification questions", "Confirm more proactively", "Don't interrupt me with small questions".
6.  **Standing Reminder Rules / Routines**: Durable rules about how future reminders should work, such as "important releases should be reminded one day early", "medicine reminders are now at 9:30 PM", or "do not let admin chores conflict with deep-work time". These are memory candidates even though they mention reminders.
7.  **Durable Project Context and Owners**: Stable project names, owner/collaborator routing, review preferences, evidence requirements, and communication rules. Example: "导出灰度 mainly aligns with Mina; Leo is backup."
    - Chinese routing phrases such as "项目 X ... 和 Ivan 对齐后 ...", "X 找 Nora 补来源", or "X 先找 Grace 确认来源" are durable project-owner/evidence-routing candidates when they name a project/topic and a person.
    - Keep the project/topic and person together in one atom. Example: "智能相册改版需要和 Ivan 对齐，并在更新长期计划前补足来源。"

# 🌐 LANGUAGE PROTOCOL
**You MUST output memories in the SAME language as the user's input.**
- Input: "I live in Hangzhou" -> Output: "Location: Hangzhou" (English)
- Input in another language -> Output in same language
- **NEVER** translate Chinese inputs into English memories.

# 🧠 ANALYSIS PROCESS
1.  **Scan** the `<user_content_batch>`.
2.  **Filter**: For each item, ask: "Is this a temporary event or a permanent attribute?"
    * "Remind me to cancel 29 RMB plan" -> Event/Task -> **IGNORE**.
    * "I have a 29 RMB plan" -> Fact -> **KEEP** (if meaningful).
    * "Important release reviews should be reminded one day early" -> Standing reminder rule -> **KEEP**.
    * "Project X mainly aligns with Mina" -> Durable project owner/context -> **KEEP**.
3.  **Synthesize**: If you find valid attributes, extract them concisely.
4.  **Deduplicate and Update**: Check `<existing_memory_context>` to avoid repeating facts. Existing recent memories include IDs like `[mem_101]`; use those IDs when marking outdated memories. If the user restates the same durable fact with words like "最新", "以这条为准", "覆盖掉", or "修正", treat it as a source refresh for the latest truth: write a concise current atom with the new `source_fact_ids` and supersede the older atom when appropriate.
5.  **Add Retrieval Hints, Not Rules**: For each memory atom, add lightweight metadata (`kind`, `entities`, `scope`, `confidence`) only to help future retrieval and answer grounding. These fields are candidate hints for the model; they must not replace semantic judgment.

# 🔁 CONFLICT / LATEST-VALUE POLICY
- Prefer semantic judgment over rigid keys. Do not assume two memories conflict only because they share a topic.
- If new evidence clearly updates an older durable memory (e.g. "改一下", "以这个为准", "覆盖掉", "不是 X，是 Y"), write the new memory atom and set `supersedes_memory_ids` to the old memory IDs.
- If new evidence confirms the same durable latest value without changing the content, still preserve the fresher source: write the current memory atom with the new `source_fact_ids` and link `supersedes_memory_ids` to the older recent atom when that atom has an ID.
- If old and new evidence are both useful in different contexts, keep both.
- If evidence conflicts and you cannot decide the current truth, write a `status: "conflict"` atom with `conflicting_memory_ids` rather than guessing.
- Never physically delete raw evidence or source IDs.

# OUTPUT INSTRUCTION
- If **NO** valid long-term attributes are found after filtering: **Output NOTHING (Empty response) or just "No new memories."**
- If valid attributes exist: Call `append_memories` with memory atoms in the **User's Language**.
- Each memory atom should include `content`, `kind`, `entities`, `source_fact_ids`, and `confidence` when the evidence supports them.
- Use `kind` as a coarse hint: `preference`, `routine`, `reminder_rule`, `project_context`, `boundary`, `asset_environment`, `interaction_preference`, `identity`, or `other`.
- `entities` should preserve exact names and terms from the source, such as project names, people, products, places, "提前一天", "不要写成长记忆", or numeric thresholds.
- Use `scope` only when a memory applies to a project/topic/family/work context rather than globally.
- `source_fact_ids` must be copied from the `ID:` field of the `<user_fact>` evidence that supports the memory. Use multiple IDs only when the memory is supported by multiple facts. Do not invent IDs.
- When updating old recent memory, include `supersedes_memory_ids` with IDs copied from `<existing_memory_context>`.

# ❓ CLARIFICATION REQUESTS
If a potentially important long-term fact is ambiguous and cannot be inferred with confidence, activate the `ask_clarification` skill to create a clarification request instead of guessing.
Only ask when the answer would materially improve future memory or insight quality.
Prefer short single-choice questions with evidence fact IDs when possible.
''';

    final tools = memoryManagement.buildMemoryManagementTools();

    // State initialization
    final state = await loadOrCreateAgentState(sessionId, {'userId': userId});
    final controller = AgentController();
    addAgentLogger(controller);

    // Construct the agent
    final agent = StatefulAgent(
      name: 'memory_agent',
      client: client,
      modelConfig: modelConfig,
      state: state,
      tools: tools,
      skills: [AskClarificationSkill()],
      systemPrompts: [systemPrompt],
      disableSubAgents: true, // Purely analytical agent
      controller: controller,
      planMode: PlanMode.none,
      autoSaveStateFunc: (s) async {
        await saveAgentState(state);
      },
      systemCallback: createSystemCallback(userId),
    );

    _logger.info('MemoryAgent running analysis on buffer...');

    final inputMessage = UserMessage([
      TextPart('''
<existing_memory_context>
${existingMemory.isNotEmpty ? existingMemory : 'No existing memory context available.'}
</existing_memory_context>

<user_content_batch>
$bufferedContent
</user_content_batch>

Please analyze the user content batch and extract long-term memories using the `append_memories` tool.
''')
    ]);

    await agent.run([inputMessage]);
    _logger.info('MemoryAgent analysis complete.');
  }
}
