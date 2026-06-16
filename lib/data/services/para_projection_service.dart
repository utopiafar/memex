import 'package:memex/data/services/file_operation_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/memory_primary_service.dart';
import 'package:memex/utils/time_context.dart';
import 'package:path/path.dart' as p;

class ParaProjectionResult {
  final String filePath;
  final int memoryCount;
  final String content;

  const ParaProjectionResult({
    required this.filePath,
    required this.memoryCount,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {
      'file_path': filePath,
      'memory_count': memoryCount,
      'content_length': content.length,
    };
  }
}

class ParaProjectionService {
  ParaProjectionService._();

  static final ParaProjectionService instance = ParaProjectionService._();

  Future<ParaProjectionResult> projectMemoryPrimaryToPara({
    required String userId,
    bool dryRun = false,
  }) async {
    final atoms = await MemoryPrimaryService.instance.listActiveAtoms(userId);
    final content = _renderProjection(userId: userId, atoms: atoms);
    final fs = FileSystemService.instance;
    final filePath = p.join(
      fs.getPkmPath(userId),
      'Memory Primary Projection.md',
    );
    if (!dryRun) {
      await FileOperationService.instance.writeFile(
        filePath: filePath,
        workingDirectory: fs.getWorkspacePath(userId),
        content: content,
      );
    }
    return ParaProjectionResult(
      filePath: filePath,
      memoryCount: atoms.length,
      content: content,
    );
  }

  String _renderProjection({
    required String userId,
    required List<MemoryAtom> atoms,
  }) {
    final now = DateTime.now();
    final groups = <String, List<MemoryAtom>>{};
    for (final atom in atoms) {
      groups.putIfAbsent(_paraBucket(atom), () => []).add(atom);
    }

    final b = StringBuffer();
    b.writeln('# Memory Primary Projection');
    b.writeln('');
    b.writeln('Generated: ${formatLocalDateTimeWithZone(now)}');
    b.writeln('User: $userId');
    b.writeln('');
    b.writeln(
      '> This document is a projection of Memory Primary, not the source of truth.',
    );
    b.writeln('');

    for (final bucket in ['Projects', 'Areas', 'Resources']) {
      final list = groups[bucket] ?? const <MemoryAtom>[];
      if (list.isEmpty) continue;
      b.writeln('## $bucket');
      b.writeln('');
      for (final atom in list) {
        final title = atom.title.trim().isEmpty ? atom.type : atom.title;
        b.writeln('### $title');
        b.writeln('');
        b.writeln(atom.content);
        b.writeln('');
        b.writeln('- memory_id: `${atom.id}`');
        b.writeln('- type: `${atom.type}`');
        b.writeln('- confidence: `${atom.confidence}`');
        b.writeln('- importance: `${atom.importance}`');
        if (atom.entityIds.isNotEmpty) {
          b.writeln(
            '- entities: ${atom.entityIds.map((e) => '`$e`').join(', ')}',
          );
        }
        if (atom.evidenceFactIds.isNotEmpty) {
          b.writeln(
            '- evidence_fact_ids: ${atom.evidenceFactIds.map((e) => '`$e`').join(', ')}',
          );
        }
        b.writeln('');
      }
    }

    return b.toString();
  }

  String _paraBucket(MemoryAtom atom) {
    switch (atom.type) {
      case 'project_context':
      case 'schedule':
      case 'reminder_rule':
        return 'Projects';
      case 'identity':
      case 'preference':
      case 'routine':
      case 'boundary':
      case 'relationship':
      case 'health':
      case 'finance':
      case 'asset_environment':
      case 'interaction_preference':
        return 'Areas';
      default:
        return 'Resources';
    }
  }
}
