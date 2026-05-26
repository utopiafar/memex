import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/time_context.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;

import 'package:logging/logging.dart';

final _logger = Logger('MemoryManagement');

class MemoryAtomDraft {
  final String content;
  final String? kind;
  final List<String> entities;
  final List<String> sourceFactIds;
  final double? confidence;
  final String? scope;
  final String? validFrom;
  final String? validUntil;
  final String status;
  final List<String> supersedesMemoryIds;
  final List<String> conflictingMemoryIds;

  const MemoryAtomDraft({
    required this.content,
    this.kind,
    this.entities = const [],
    this.sourceFactIds = const [],
    this.confidence,
    this.scope,
    this.validFrom,
    this.validUntil,
    this.status = 'active',
    this.supersedesMemoryIds = const [],
    this.conflictingMemoryIds = const [],
  });

  factory MemoryAtomDraft.fromToolInput(dynamic input) {
    if (input is String) {
      return MemoryAtomDraft(content: input);
    }
    if (input is Map) {
      final content = input['content']?.toString() ??
          input['memory']?.toString() ??
          input['text']?.toString() ??
          '';
      final sourceFactIds = _firstStringList(
        input,
        const ['source_fact_ids', 'source_ids', 'source_references'],
      );
      final status = _normalizeStatus(input['status']?.toString());
      return MemoryAtomDraft(
        content: content,
        kind: _normalizeKind(input['kind']?.toString()),
        entities: _stringList(input['entities']),
        sourceFactIds: sourceFactIds,
        confidence: _normalizeConfidence(input['confidence']),
        scope: _cleanString(input['scope']?.toString()),
        validFrom: _cleanString(input['valid_from']?.toString()),
        validUntil: _cleanString(input['valid_until']?.toString()),
        status: status,
        supersedesMemoryIds: _stringList(input['supersedes_memory_ids']),
        conflictingMemoryIds: _stringList(input['conflicting_memory_ids']),
      );
    }
    return MemoryAtomDraft(content: input?.toString() ?? '');
  }

  static String _normalizeStatus(String? value) {
    final normalized = value?.trim();
    if (normalized == 'conflict') return 'conflict';
    return 'active';
  }

  static String? _normalizeKind(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    const allowed = {
      'identity',
      'preference',
      'routine',
      'reminder_rule',
      'project_context',
      'boundary',
      'asset_environment',
      'interaction_preference',
      'other',
    };
    return allowed.contains(normalized) ? normalized : 'other';
  }

  static double? _normalizeConfidence(dynamic value) {
    if (value == null) return null;
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null) return null;
    return parsed.clamp(0.0, 1.0).toDouble();
  }

  static String? _cleanString(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final id = item.toString().trim();
      if (id.isNotEmpty && seen.add(id)) {
        result.add(id);
      }
    }
    return result;
  }

  static List<String> _firstStringList(Map input, List<String> keys) {
    for (final key in keys) {
      final values = _stringList(input[key]);
      if (values.isNotEmpty) return values;
    }
    return const [];
  }
}

class MemoryManagement {
  final String userId;
  final String sourceAgent;
  final FileSystemService fileSystem;
  final LLMClient client;
  final ModelConfig modelConfig;
  final int recentBufferThreshold;

  MemoryManagement({
    required this.userId,
    required this.sourceAgent,
    required this.client,
    required this.modelConfig,
    this.recentBufferThreshold = 10,
    FileSystemService? fileSystem,
  }) : fileSystem = fileSystem ?? FileSystemService.instance;

  static Future<MemoryManagement> createDefault({
    required String userId,
    required String sourceAgent,
    FileSystemService? fileSystem,
  }) async {
    final resources = await UserStorage.getAgentLLMResources(
      AgentDefinitions.profileAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );

    return MemoryManagement(
      userId: userId,
      sourceAgent: sourceAgent,
      client: resources.client,
      modelConfig: resources.modelConfig,
      fileSystem: fileSystem,
    );
  }

  // Static lock map to handle concurrency across different MemoryManagement instances
  static final Map<String, Future<void>> _locks = {};

  Future<T> _withLock<T>(String key, Future<T> Function() operation) async {
    while (_locks.containsKey(key)) {
      await _locks[key]!;
    }

    final completer = Completer<void>();
    _locks[key] = completer.future;

    try {
      return await operation();
    } finally {
      completer.complete();
      _locks.remove(key);
    }
  }

  Future<T> _runWithMemoryLock<T>(Future<T> Function() operation) async {
    final path = _getMemoryPath();
    return _withLock(path, operation);
  }

  String _getMemoryPath() {
    return p.join(fileSystem.getSystemPath(userId), 'memory', 'memory.json');
  }

  Future<Map<String, dynamic>> _loadMemory() async {
    final path = _getMemoryPath();
    final file = File(path);
    if (!await file.exists()) {
      return {
        "user_id": userId,
        "last_updated": DateTime.now().toIso8601String(),
        "next_mem_id": 101,
        "archived_memory": "",
        "archived_atoms": [],
        "recent_buffer": [],
      };
    }

    try {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      // In case of error/corruption, return default structure but maybe log warning?
      // For now, robust fallback.
      return {
        "user_id": userId,
        "last_updated": DateTime.now().toIso8601String(),
        "next_mem_id": 101,
        "archived_memory": "",
        "archived_atoms": [],
        "recent_buffer": [],
      };
    }
  }

  Future<void> _writeMemory(Map<String, dynamic> memory) async {
    final path = _getMemoryPath();
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    // Update timestamp
    memory['last_updated'] = DateTime.now().toIso8601String();

    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(memory));
  }

  Future<String> appendMemories(
    List<String> memories, {
    List<String> sourceFactIds = const [],
  }) async {
    return appendMemoryAtoms(
      memories
          .map(
            (memory) => MemoryAtomDraft(
              content: memory,
              sourceFactIds: sourceFactIds,
            ),
          )
          .toList(),
    );
  }

  Future<String> appendMemoryAtoms(List<MemoryAtomDraft> memories) async {
    return _runWithMemoryLock(() async {
      var mem = await _loadMemory();
      final buffer = (mem['recent_buffer'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final archivedAtoms = (mem['archived_atoms'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];

      int nextId = (mem['next_mem_id'] as int?) ?? 101;
      final addedIds = <String>[];

      for (final memory in memories) {
        final m = memory.content.trim();
        if (m.isEmpty) continue;

        final memoryId = "mem_$nextId";
        nextId++;

        final newEntry = <String, dynamic>{
          "memory_id": memoryId,
          "content": m,
          "source_agent": sourceAgent,
          "created_at": DateTime.now().toIso8601String(),
        };
        if (memory.kind != null) {
          newEntry["kind"] = memory.kind;
        }
        if (memory.entities.isNotEmpty) {
          newEntry["entities"] = memory.entities;
        }
        if (memory.status != 'active') {
          newEntry["status"] = memory.status;
        }
        if (memory.sourceFactIds.isNotEmpty) {
          newEntry["source_fact_ids"] = memory.sourceFactIds;
        }
        if (memory.confidence != null) {
          newEntry["confidence"] = memory.confidence;
        }
        if (memory.scope != null) {
          newEntry["scope"] = memory.scope;
        }
        if (memory.validFrom != null) {
          newEntry["valid_from"] = memory.validFrom;
        }
        if (memory.validUntil != null) {
          newEntry["valid_until"] = memory.validUntil;
        }
        if (memory.supersedesMemoryIds.isNotEmpty) {
          newEntry["supersedes_memory_ids"] = memory.supersedesMemoryIds;
          _markSuperseded(
            buffer,
            supersededIds: memory.supersedesMemoryIds,
            supersededByMemoryId: memoryId,
          );
          _markSuperseded(
            archivedAtoms,
            supersededIds: memory.supersedesMemoryIds,
            supersededByMemoryId: memoryId,
          );
        }
        if (memory.conflictingMemoryIds.isNotEmpty) {
          newEntry["conflicting_memory_ids"] = memory.conflictingMemoryIds;
        }

        buffer.add(newEntry);
        addedIds.add(memoryId);
      }

      mem['next_mem_id'] = nextId;
      mem['recent_buffer'] = buffer;
      mem['archived_atoms'] = archivedAtoms;

      String resultMsg =
          "Memories appended successfully. IDs: ${addedIds.join(', ')}";

      if (buffer.length > recentBufferThreshold) {
        try {
          mem = await _summarizeMemory(mem);
          resultMsg += "\n(Memory buffer consolidated to archive)";
        } catch (e) {
          resultMsg += "\n(Memory consolidation failed: $e)";
        }
      }

      await _writeMemory(mem);
      return resultMsg;
    });
  }

  void _markSuperseded(
    List<Map<String, dynamic>> buffer, {
    required List<String> supersededIds,
    required String supersededByMemoryId,
  }) {
    final targetIds = supersededIds.toSet();
    final now = DateTime.now().toIso8601String();
    for (final entry in buffer) {
      final memoryId = entry['memory_id']?.toString();
      if (memoryId == null || !targetIds.contains(memoryId)) continue;
      entry['status'] = 'superseded';
      entry['superseded_at'] = now;
      entry['superseded_by_memory_id'] = supersededByMemoryId;
    }
  }

  List<Tool> buildMemoryManagementTools() {
    return [
      Tool(
        name: 'append_memories',
        description:
            'Records permanent facts, preferences, or plans into the user\'s long-term profile. DO NOT record transient context (e.g., "User is asking about X") or chat logs. ONLY record enduring information that will be useful for future sessions. Support batch addition.',
        parameters: {
          'type': 'object',
          'properties': {
            'memories': {
              'type': 'array',
              'description':
                  'List of memory atoms to add. Prefer objects with content and source_fact_ids. String items are accepted for backward compatibility. Each content string should be an atomic fact using 3rd person perspective. AVOID "User said". BAD: "User said he likes Python". GOOD: "Preferred programming language is Python".',
              'items': {
                'oneOf': [
                  {'type': 'string'},
                  {
                    'type': 'object',
                    'properties': {
                      'content': {
                        'type': 'string',
                        'description': 'Atomic memory content.',
                      },
                      'source_fact_ids': {
                        'type': 'array',
                        'description':
                            'Concrete fact IDs that support this memory atom.',
                        'items': {'type': 'string'},
                      },
                      'kind': {
                        'type': 'string',
                        'enum': [
                          'identity',
                          'preference',
                          'routine',
                          'reminder_rule',
                          'project_context',
                          'boundary',
                          'asset_environment',
                          'interaction_preference',
                          'other',
                        ],
                        'description':
                            'Lightweight retrieval hint for the atom. This is not a hard routing rule.',
                      },
                      'entities': {
                        'type': 'array',
                        'description':
                            'Important people, projects, places, topics, or exact terms mentioned in this memory atom.',
                        'items': {'type': 'string'},
                      },
                      'confidence': {
                        'type': 'number',
                        'description':
                            '0-1 confidence that the memory is durable and current. Use only when the evidence supports it.',
                      },
                      'scope': {
                        'type': 'string',
                        'description':
                            'Optional natural-language scope, such as a project/topic/family/work context.',
                      },
                      'valid_from': {
                        'type': 'string',
                        'description':
                            'Optional ISO date/time or source phrase for when this memory starts to apply.',
                      },
                      'valid_until': {
                        'type': 'string',
                        'description':
                            'Optional ISO date/time or source phrase for when this memory stops applying.',
                      },
                      'status': {
                        'type': 'string',
                        'enum': ['active', 'conflict'],
                        'description':
                            'Use active for normal current memories. Use conflict only when evidence conflicts and you cannot decide the latest truth.',
                      },
                      'supersedes_memory_ids': {
                        'type': 'array',
                        'description':
                            'Existing memory IDs this atom should replace because the new evidence clearly makes them outdated.',
                        'items': {'type': 'string'},
                      },
                      'conflicting_memory_ids': {
                        'type': 'array',
                        'description':
                            'Existing memory IDs related to an unresolved conflict.',
                        'items': {'type': 'string'},
                      },
                    },
                    'required': ['content', 'source_fact_ids'],
                  },
                ],
              },
            },
          },
          'required': ['memories'],
        },
        executable: (List<dynamic> memories) async {
          return appendMemoryAtoms(
            memories.map(MemoryAtomDraft.fromToolInput).toList(),
          );
        },
      ),
    ];
  }

  Future<Map<String, dynamic>> _summarizeMemory(
      Map<String, dynamic> memory) async {
    final archived = memory['archived_memory'] as String? ?? '';
    final archivedAtoms = (memory['archived_atoms'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    final buffer = (memory['recent_buffer'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    if (buffer.isEmpty) return memory;

    final itemsToConsolidate = buffer;
    final itemsToKeep = <Map<String, dynamic>>[];

    if (itemsToConsolidate.isEmpty) return memory;

    final currentTime = DateTime.now();
    final summarizeStrings = _memorySummarizeStrings();

    final itemsBuffer = StringBuffer();
    for (final item in itemsToConsolidate) {
      if (item['status'] == 'superseded') continue;
      final sourceFactIds = (item['source_fact_ids'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList() ??
          const <String>[];
      final sourceSuffix = sourceFactIds.isEmpty
          ? ''
          : ' (sources: ${sourceFactIds.join(', ')})';
      final kind = item['kind']?.toString();
      final entities = (item['entities'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList() ??
          const <String>[];
      final hintSuffix = [
        if (kind != null && kind.trim().isNotEmpty) 'kind: $kind',
        if (entities.isNotEmpty) 'entities: ${entities.join(', ')}',
        if (item['scope'] != null) 'scope: ${item['scope']}',
      ].join('; ');
      final status = item['status']?.toString();
      final statusSuffix =
          status == null || status == 'active' ? '' : ' (status: $status)';
      final metadataSuffix = hintSuffix.isEmpty ? '' : ' [$hintSuffix]';
      itemsBuffer.writeln(
        '- [${item['created_at']}] ${item['content']}$sourceSuffix$statusSuffix$metadataSuffix',
      );
    }

    final prompt = '''Role: You are an expert **User Profile Builder**.
Task: Synthesize "Short-term Memories" into a cohesive "User Profile".
Goal: **Summarize and compress** information to build a high-fidelity persona. Do NOT create a daily log.

## Context Data:
Current Local Time: ${formatLocalDateTimeWithZone(currentTime)}

## Current Profile (Markdown):
${archived.isEmpty ? '(Empty - Initialize new)' : archived}

## New Information Buffer:
${itemsBuffer.toString()}

## Processing Rules (STRICT):

1.  **Profiling over Logging (CRITICAL)**:
    -   **Convert Events to Attributes**: Do not record *what happened*. Record *what it means*.
    -   *Bad*: "User asked about OpenWrt settings on Monday." -> This is a Log.
    -   *Good*: "Tech Stack: Familiar with OpenWrt & Network configuration." -> This is a Profile.
    -   **Transformation**: Extract the User's Identity, Skills, Preferences, and Constraints from the raw events.

2.  **Aggressive Merging (Summary)**:
    -   **Combine Related Items**: If the buffer has 5 entries about "Router setup", summarize them into **ONE** bullet point defining the user's network setup.
    -   **Update Status**: If new info contradicts old info (e.g., location changed), **overwrite** the old info. Keep only the latest state.
    -   **Discard Noise**: Remove specific timestamps, one-off transaction IDs, and transient emotions.
    -   **Preserve Evidence Hints**: When a high-value profile bullet is supported by source IDs or important named entities, keep those IDs/entities compactly near that bullet. They are retrieval hints, not display prose.

3.  **Language Consistency**:
    -   ${summarizeStrings.languageInstruction}
    -   Keep technical terms (like "Python", "OpenWrt") in English where appropriate.

4.  **Output Structure**:
    -   Organize the summary using these logical headers (or similar):
        -   `${summarizeStrings.identityHeader}`: Basic info, roles, family status.
        -   `${summarizeStrings.interestsHeader}`: Tech stack, hobbies, professional skills.
        -   `${summarizeStrings.assetsHeader}`: Devices, hardware, location, home setup.
        -   `${summarizeStrings.focusHeader}`: Active goals or immediate plans (summarized).
    -   Use concise bullet points.

5.  **Output**:
    -   Return ONLY the updated Markdown text. Do not wrap in markdown code blocks.
    -   **CRITICAL**: You must output the **FULL, MERGED Profile**. Do not output just the changes. The output should be a valid, standalone Markdown document that replaces the old profile entirely.
    -   **CONSTRAINT**: Keep the entire profile concise, ideally under 1000 words. Prune less important details if necessary to fit.
''';

    try {
      final response = await client.generate(
        [
          UserMessage([TextPart(prompt)])
        ],
        modelConfig: modelConfig,
      );

      var rawOutput = response.textOutput?.trim() ?? '';
      if (rawOutput.startsWith('```')) {
        rawOutput =
            rawOutput.replaceAll(RegExp(r'^```(markdown)?|```$'), '').trim();
      }

      // Auto-condense if output is too long (approx 1000 words -> 3000~4000 chars mixed context)
      if (rawOutput.length > 4000) {
        _logger.info(
            'Profile too long (${rawOutput.length} chars). Requesting condensation.');

        final condensePrompt = '''
You are an expert editor.
The following user profile is too long (${rawOutput.length} characters).
Please condense it to under 2000 characters while strictly preserving the key attributes (Identity, Skills, Preferences).
Discard verbose timestamps or minor details.

Profile to condense:
"""
$rawOutput
"""

Output ONLY the condensed Markdown.
''';

        try {
          final condenseResponse = await client.generate(
            [
              UserMessage([TextPart(condensePrompt)])
            ],
            modelConfig: modelConfig,
          );

          final condensedOutput = condenseResponse.textOutput?.trim() ?? '';
          if (condensedOutput.isNotEmpty) {
            var finalOutput = condensedOutput;
            if (finalOutput.startsWith('```')) {
              finalOutput = finalOutput
                  .replaceAll(RegExp(r'^```(markdown)?|```$'), '')
                  .trim();
            }
            rawOutput = finalOutput;
            _logger.info('Profile condensed to ${rawOutput.length} chars.');
          }
        } catch (e) {
          _logger.warning('Failed to condense profile: $e');
        }
      }

      final newArchived = rawOutput;

      if (newArchived.isNotEmpty) {
        memory['archived_memory'] = newArchived;
        final mergedArchivedAtoms = [
          ...archivedAtoms,
          ...itemsToConsolidate.where((item) => item['status'] != 'superseded'),
        ];
        memory['archived_atoms'] = _dedupeArchivedAtoms(
          mergedArchivedAtoms,
        ).takeLast(200).toList(growable: false);
        memory['recent_buffer'] = itemsToKeep;
      }
    } catch (e) {
      _logger.severe('Memory consolidation failed: $e');
    }

    return memory;
  }

  Future<String> buildMemoryManagementPrompt() async {
    return '''## Memory System Capabilities (Background Process)
You possess a long-term memory system as a **secondary, background capability**.
**Primary Directive**: Your main priority is ALWAYS to fulfill the user's immediate request (answering questions, coding, chatting, etc.) accurately and helpfully.
**Secondary Directive (The "Silent Observer")**: 
While executing your primary directive, **silently observe** the conversation for high-value information to update the User Profile.
- **Do NOT** let this background task interfere with the quality or tone of your main response.
- **Do NOT** ask the user follow-up questions solely to populate the memory.

---
### 🧠 Core Memory Logic
1. **Recall**: Use the context provided in the `<user_memory_context>` block to tailor your responses.
2. **Record (Analytic & Selective)**: 
   - **Trigger Condition**: Use the `append_memories` tool **IF AND ONLY IF** you detect new information with clear **Long-term Strategic Value**.
   - **Source Links**: When durable evidence includes concrete fact IDs, pass each memory as an object with `content` and `source_fact_ids`. Preserve source IDs exactly; never invent them. If no source fact ID is available, use an empty `source_fact_ids` list.
   - **Conflict Updates**: If new durable evidence clearly updates an existing recent memory, pass the new atom with `supersedes_memory_ids` containing the old memory IDs. If the evidence conflicts but the latest truth is unclear, pass `status: "conflict"` and `conflicting_memory_ids` instead of guessing. Do not rely on rigid keys; judge from the wording and evidence.
   - **Analyst Mindset**: Do not act as a passive scribe. Look for patterns and attributes (e.g., "User buys expensive gear" -> "High spending power"), rather than just logging events.
   - **AI Interaction Preferences**: Treat durable preferences about how the AI should interact as memory candidates, such as asking fewer clarification questions, confirming more proactively, or avoiding small interruptions.
   - **The "Silence is Okay" Rule**: If the conversation is casual, transactional, or contains no new profile data, **DO NOT call the tool**. It is better to record *nothing* than to fill the memory with noise.

   #### Recording Rules (Strict Filters)
   
   **Rule 1: The "7-Day Validity" Test** (Time Filter)
   Before calling the tool, ask: *"Will this fact still be useful guidance for me 7 days from now?"*
   - YES -> It's a candidate for memory.
   - NO -> Discard it. (e.g., "I'm hungry", "Traffic is bad", "I'm testing this code").
   - **EXCEPTION**: Record **Upcoming Events** (flights, deadlines) regardless of the 7-day rule as they impact the immediate future.

   **Rule 2: The "Profile vs. Diary" Test** (Abstraction Filter)
   - **Diary (DON'T RECORD)**: Specific timestamps, transaction logs, invoice numbers, daily OOTD, fluctuating prices (e.g., stock price today).
   - **Profile (DO RECORD)**: The *attributes* implied by those events.
     - *Raw Event*: "Bought a \$2000 coffee machine."
     - *Memory*: "User is a coffee enthusiast and values high-end appliances." (Extract the **Trait**, not just the Receipt).

   **Rule 3: The "Implicit Insight" Rule** (Inference)
   - Capture what the user *implies* but doesn't say.
   - *User says*: "Can you make the font bigger? My eyes hurt."
   - *Memory*: "User has visual accessibility needs/prefers large text."

   **Rule 4: The "Dual-Write" Requirement**
   - Even if you produced a file/artifact for the user, if the *context* of that task defines the user (e.g., "Working on Project X"), record the *context* to memory.

   #### ❌ Explicit Exclusion List (Do NOT Record)
   - **Transactional Noise**: Invoice IDs, receipt numbers, courier tracking codes.
   - **Transient Data**: Current weather, specific stock prices (unless analyzing trends), random daily thoughts.
   - **Completed Chores**: "I took out the trash" (Zero long-term value).

   #### Case Studies: How to Think Like a Profiler
    
    **Case 1: The "Financial Noise" Trap**
    - **User Input**: "Bought 6 knife items on Dec 12 2025, total 598.3, 5 pending shipment."
    - **❌ WRONG Way (Accountant)**: "Dec 12 2025 knife purchase 598.3." (Reason: Records transient price and date.)
    - **✅ RIGHT Way (Profiler)**: 
      1. *Analyze*: Price and Date are noise. Status (Shipping) is transient.
      2. *Extract*: User buys *multiple* knives -> User collects knives.
      3. *Memory*: "Interest: **knife collection**."

    **Case 2: The "Stock Snapshot" Trap**
    - **User Input**: "Moor thread closed at 814.88, down 13.41%, think A-shares have a bubble."
    - **❌ WRONG Way (Logger)**: "Record Moor thread 814.88, market cap 383B..." (Reason: Prices change every second. Junk data tomorrow.)
    - **✅ RIGHT Way (Profiler)**:
      1. *Analyze*: Specific numbers are snapshots. Delete them.
      2. *Extract*: User pays attention to this stock + negative view on market.
      3. *Memory*: "Investment view: follows **Moor thread**, sees A-shares bubble."

    **Case 3: The "Language Match" Trap**
    - **User Input**: "I don't like cilantro."
    - **❌ WRONG Way (Translator)**: "User dislikes coriander." (Reason: Language mismatch.)
    - **✅ RIGHT Way (Native Speaker)**: "Food preference: dislikes **cilantro**."

    **Case 4: The "Implicit Trait" Extraction**
    - **User Input**: "My portfolio has NVDA and Tencent."
    - **✅ RIGHT Way**: "Investment Interest: Holds **US Tech (NVDA)** and **HK Tech (Tencent)**." (Focus on the *Sector* and *Asset Class*, not the account balance).
''';
  }

  Future<String> buildSuperAgentMemoryManagementPrompt() async {
    final basePrompt = await buildMemoryManagementPrompt();
    return '''$basePrompt

## SuperAgent Memory Boundary (Conservative Mode)
SuperAgent often searches and summarizes existing workspace history. Apply these extra rules when deciding whether to call `append_memories`:
- Treat retrieved Facts, PKM files, chat history, existing memory, and event logs as read-only evidence. Do not convert them into new memories by themselves.
- Only write memory when the current conversation introduces or explicitly confirms durable user profile information, or when the user explicitly asks you to remember/update memory.
- Deduplicate against `<user_memory_context>`; do not rewrite or paraphrase information that is already known.
''';
  }

  Future<String> buildMemoryReadOnlyPrompt() async {
    return '''## Memory System Capabilities (Read-Only Context)
You have access to the user's long-term memory context as **reference material only**.
**Primary Directive**: Use the `<user_memory_context>` block to tailor your response to the user's preferences, active projects, and constraints.

---
### 🧠 Core Memory Logic
1. **Recall Only**: Use the context provided in the `<user_memory_context>` block to answer the user's immediate request accurately and helpfully.
2. **No Memory Updates**: You cannot and must not create, update, delete, or propose changes to memory in this mode.
3. **Read-Only Task Boundary**: When searching, summarizing, listing, or comparing existing Facts/PKM/history/chat records, treat all retrieved information as read-only evidence for the answer, not as new memory candidates.
''';
  }

  Future<String> buildMemoryPrompt() async {
    return _runWithMemoryLock(() async {
      final mem = await _loadMemory();
      final archived = mem['archived_memory'] as String? ?? '';
      final archivedAtoms = (mem['archived_atoms'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];

      final buffer = (mem['recent_buffer'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];

      if (archived.isEmpty && buffer.isEmpty) {
        return "";
      }

      final sb = StringBuffer();

      sb.writeln('<user_memory_context>');
      sb.writeln(
          'The following is the user\'s long-term profile and recent context.');
      sb.writeln('');

      if (archived.isNotEmpty) {
        sb.writeln('### 🧠 Long-term Profile (Established Facts)');
        sb.writeln(archived);
        sb.writeln('');
      }

      final activeArchivedAtoms = archivedAtoms
          .where((item) => item['status'] != 'superseded')
          .toList(growable: false);
      if (activeArchivedAtoms.isNotEmpty) {
        sb.writeln('### 🔎 Archived Memory Atoms (Structured Retrieval Hints)');
        for (final item in activeArchivedAtoms.takeLast(30)) {
          final memoryId = item['memory_id']?.toString() ?? 'archived_memory';
          final sourceFactIds = (item['source_fact_ids'] as List?)
                  ?.map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .toList() ??
              const <String>[];
          final sourceSuffix = sourceFactIds.isEmpty
              ? ''
              : ' (sources: ${sourceFactIds.join(', ')})';
          sb.writeln(
            '- [$memoryId] ${item['content']}$sourceSuffix${_memoryMetadataLine(item)}',
          );
        }
        sb.writeln('');
      }

      if (buffer.isNotEmpty) {
        sb.writeln('### 📝 Recent Working Memory (New & Unprocessed)');

        for (final item in buffer) {
          if (item['status'] == 'superseded') continue;
          final timeStr = item['created_at'] ?? '';
          final shortTime =
              timeStr.length > 16 ? timeStr.substring(0, 16) : timeStr;
          final memoryId = item['memory_id']?.toString() ?? 'unknown_memory';
          final status = item['status']?.toString() ?? 'active';
          final sourceFactIds = (item['source_fact_ids'] as List?)
                  ?.map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .toList() ??
              const <String>[];
          final sourceSuffix = sourceFactIds.isEmpty
              ? ''
              : ' (sources: ${sourceFactIds.join(', ')})';
          final statusSuffix = status == 'active' ? '' : ' (status: $status)';
          final metadata = _memoryMetadataLine(item);

          sb.writeln(
            '- [$memoryId][$shortTime] ${item['content']}$sourceSuffix$statusSuffix$metadata',
          );
          final evidence = await _sourceFactEvidenceBlock(sourceFactIds);
          if (evidence.isNotEmpty) {
            sb.writeln(evidence);
          }
        }
        sb.writeln('');
      }

      sb.writeln('</user_memory_context>');

      if (archived.isNotEmpty || buffer.isNotEmpty) {
        sb.writeln(
            '**Context Instruction**: The above information defines the user\'s preferences, active projects, and constraints. You must adapt your response to align with this profile.');
      }

      return sb.toString();
    });
  }

  String _memoryMetadataLine(Map<String, dynamic> item) {
    final parts = <String>[];
    final kind = item['kind']?.toString().trim();
    if (kind != null && kind.isNotEmpty) parts.add('kind=$kind');
    final entities = (item['entities'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    if (entities.isNotEmpty) parts.add('entities=${entities.join('|')}');
    final scope = item['scope']?.toString().trim();
    if (scope != null && scope.isNotEmpty) parts.add('scope=$scope');
    final confidence = item['confidence'];
    if (confidence != null) parts.add('confidence=$confidence');
    final validFrom = item['valid_from']?.toString().trim();
    if (validFrom != null && validFrom.isNotEmpty) {
      parts.add('valid_from=$validFrom');
    }
    final validUntil = item['valid_until']?.toString().trim();
    if (validUntil != null && validUntil.isNotEmpty) {
      parts.add('valid_until=$validUntil');
    }
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }

  Future<String> _sourceFactEvidenceBlock(List<String> sourceFactIds) async {
    if (sourceFactIds.isEmpty) return '';
    final lines = <String>[];
    for (final sourceFactId in sourceFactIds.take(3)) {
      try {
        final fact = await fileSystem.extractFactContentFromFile(
          userId,
          sourceFactId,
        );
        final content = fact?.content.trim();
        if (content == null || content.isEmpty) continue;
        lines.add(
          '  source[$sourceFactId]: ${_compactEvidence(content, maxChars: 240)}',
        );
      } catch (_) {
        // Source expansion is opportunistic; memory recall should not fail
        // because a Fact was moved, deleted in a fixture, or unreadable.
      }
    }
    return lines.join('\n');
  }

  String _compactEvidence(String text, {required int maxChars}) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxChars) return compact;
    return '${compact.substring(0, maxChars)}...';
  }

  List<Map<String, dynamic>> _dedupeArchivedAtoms(
    List<Map<String, dynamic>> atoms,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    final withoutId = <Map<String, dynamic>>[];
    for (final atom in atoms) {
      final id = atom['memory_id']?.toString();
      if (id == null || id.isEmpty) {
        withoutId.add(atom);
      } else {
        byId[id] = atom;
      }
    }
    return [...withoutId, ...byId.values];
  }

  ({
    String languageInstruction,
    String identityHeader,
    String interestsHeader,
    String assetsHeader,
    String focusHeader,
  }) _memorySummarizeStrings() {
    try {
      final l10n = UserStorage.l10n;
      return (
        languageInstruction: l10n.memorySummarizeLanguageInstruction,
        identityHeader: l10n.memorySummarizeIdentityHeader,
        interestsHeader: l10n.memorySummarizeInterestsHeader,
        assetsHeader: l10n.memorySummarizeAssetsHeader,
        focusHeader: l10n.memorySummarizeFocusHeader,
      );
    } catch (_) {
      return (
        languageInstruction:
            'Use the same language as the source memories and current profile.',
        identityHeader: 'Identity',
        interestsHeader: 'Interests',
        assetsHeader: 'Assets',
        focusHeader: 'Current Focus',
      );
    }
  }
}
