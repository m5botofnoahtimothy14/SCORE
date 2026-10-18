// Leadership tier: read-only view of the school's files.
//
// Migration 00018 lets admins/leadership read `attachments` metadata for their
// own school. Object storage is private and this surface deliberately does not
// mint signed URLs — it lists what the school holds, when it arrived and where
// it is in the moderation pipeline, and says so when a row is tapped.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

const _kAllFiles = 'all';
const _kApproved = 'approved';
const _kPendingScan = 'pending_scan';
const _kQuarantined = 'quarantined';

/// Status filters offered to leadership, in severity order after "All".
const _fileFilters = <String>[_kAllFiles, _kApproved, _kPendingScan, _kQuarantined];

/// Every file uploaded at the signed-in user's school, newest first.
final _schoolFilesProvider = FutureProvider<List<SchoolFile>>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final client = Supabase.instance.client;

  final rows = await client
      .from('attachments')
      .select('id, file_name, mime_type, size_bytes, type, status, created_at, uploader_id')
      .eq('school_id', identity.schoolId)
      .order('created_at', ascending: false) as List;

  return rows.map((row) {
    final m = Map<String, dynamic>.from(row as Map);
    final size = m['size_bytes'];
    return SchoolFile(
      id: (m['id'] ?? '').toString(),
      fileName: (m['file_name'] ?? 'Untitled file').toString(),
      mimeType: (m['mime_type'] ?? '').toString(),
      sizeBytes: size is int ? size : int.tryParse((size ?? '').toString()),
      type: (m['type'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      uploaderId: (m['uploader_id'] ?? '').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
    );
  }).toList();
});

Future<void> _refreshFiles(WidgetRef ref) async {
  ref.invalidate(_schoolFilesProvider);
  try {
    await ref.read(_schoolFilesProvider.future);
  } catch (_) {
    // Surfaced by the error state on the next build.
  }
}

/// One row of `attachments` — metadata only, never the bytes.
class SchoolFile {
  final String id;
  final String fileName;
  final String mimeType;
  final int? sizeBytes;
  final String type;
  final String status;
  final String uploaderId;
  final DateTime? createdAt;

  const SchoolFile({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.type,
    required this.status,
    required this.uploaderId,
    required this.createdAt,
  });
}

/// Read-only inventory of the school's uploaded files.
class SchoolFilesScreen extends ConsumerWidget {
  const SchoolFilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final identity = identityAsync.valueOrNull;

    if (identity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('School files')),
        body: identityAsync.hasError
            ? ErrorView(
                message: identityAsync.error is IdentityException
                    ? (identityAsync.error! as IdentityException).message
                    : 'Could not load your profile. Try again.',
                onRetry: () => ref.invalidate(identityProvider),
              )
            : const LoadingView(),
      );
    }

    // Students reach their own files through conversations instead.
    if (identity.tier == AppTier.student) {
      return Scaffold(
        appBar: AppBar(title: const Text('School files')),
        body: const EmptyView(
          title: 'Not available',
          subtitle: 'The school file inventory is for teachers and school leadership.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return _SchoolFilesBody(identity: identity);
  }
}

class _SchoolFilesBody extends ConsumerStatefulWidget {
  final AppIdentity identity;
  const _SchoolFilesBody({required this.identity});

  @override
  ConsumerState<_SchoolFilesBody> createState() => _SchoolFilesBodyState();
}

class _SchoolFilesBodyState extends ConsumerState<_SchoolFilesBody> {
  String _filter = _kAllFiles;

  AppIdentity get identity => widget.identity;

  void _explainNoDownload(SchoolFile file) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Downloads are not available on mobile. "${file.fileName}" is held in '
            'private storage — open the web console to view it.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = TierAccent.of(identity.tier);
    final filesAsync = ref.watch(_schoolFilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('School files')),
      body: filesAsync.when(
        loading: () => const LoadingView(message: 'Loading school files...'),
        error: (e, _) => ErrorView(
          message: e is PostgrestException
              ? _describeFileError(e)
              : 'Could not load the school files. Try again.',
          onRetry: () => ref.invalidate(_schoolFilesProvider),
        ),
        data: (files) {
          final filtered =
              _filter == _kAllFiles ? files : files.where((f) => f.status == _filter).toList();

          final pendingScan = files.where((f) => f.status == _kPendingScan).length;
          final quarantined = files.where((f) => f.status == _kQuarantined).length;
          final totalBytes = files.fold<int>(0, (sum, f) => sum + (f.sizeBytes ?? 0));

          return RefreshIndicator(
            onRefresh: () => _refreshFiles(ref),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                GlossHero(
                  accent: accent,
                  eyebrow: 'School files',
                  title: '${files.length} ${files.length == 1 ? 'file' : 'files'}',
                  subtitle: identity.schoolName.isEmpty
                      ? 'Metadata only — files stay in private storage.'
                      : '${identity.schoolName} · metadata only, files stay in private storage.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 124,
                        child: MetricTile(
                          icon: Icons.folder_outlined,
                          label: 'Total size',
                          value: _formatBytes(totalBytes),
                          accent: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 124,
                        child: MetricTile(
                          icon: Icons.shield_outlined,
                          label: 'Pending scan',
                          value: '$pendingScan',
                          accent: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 124,
                        child: MetricTile(
                          icon: Icons.gpp_bad_outlined,
                          label: 'Quarantined',
                          value: '$quarantined',
                          accent: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _fileFilters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = _fileFilters[i];
                      final selected = _filter == f;
                      final count =
                          f == _kAllFiles ? files.length : files.where((x) => x.status == f).length;
                      return FilterChip(
                        showCheckmark: false,
                        selected: selected,
                        label: Text('${_prettyFilter(f)} ($count)'),
                        onSelected: (_) => setState(() => _filter = f),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${filtered.length} of ${files.length} shown',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  SizedBox(
                    height: 220,
                    child: EmptyView(
                      title: files.isEmpty ? 'No files yet' : 'Nothing in this state',
                      subtitle: files.isEmpty
                          ? 'Files shared in classes and messages show up here.'
                          : 'Try a different status filter.',
                      icon: Icons.folder_off_outlined,
                    ),
                  )
                else
                  for (final file in filtered) ...[
                    _FileCard(file: file, accent: accent, onTap: () => _explainNoDownload(file)),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: theme.textTheme.bodySmall?.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This screen lists file details only. Opening or downloading a '
                        'file is not supported here.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One attachment as a metadata card.
class _FileCard extends StatelessWidget {
  final SchoolFile file;
  final TierAccent accent;
  final VoidCallback onTap;

  const _FileCard({required this.file, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (fg, bg) = _statusColours(theme, file.status);
    final kind = _prettyFilter(file.type);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accent.soft,
                ),
                child: Icon(_iconFor(file), size: 20, color: accent.onSoft),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (kind.isNotEmpty) kind,
                        _formatBytes(file.sizeBytes),
                        _formatStamp(file.createdAt),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Pill(label: _prettyFilter(file.status), fg: fg, bg: bg),
                        if (file.mimeType.isNotEmpty)
                          _Pill(
                            label: file.mimeType,
                            fg: theme.colorScheme.onSurfaceVariant,
                            bg: theme.colorScheme.surfaceContainerHighest,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  const _Pill({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Semantic colour per moderation state, falling back to neutral chrome.
(Color, Color) _statusColours(ThemeData theme, String status) => switch (status) {
      _kApproved => (AppColors.success, AppColors.success.withValues(alpha: 0.10)),
      _kPendingScan => (AppColors.warning, AppColors.warning.withValues(alpha: 0.12)),
      _kQuarantined => (AppColors.danger, AppColors.danger.withValues(alpha: 0.10)),
      _ => (theme.colorScheme.onSurfaceVariant, theme.colorScheme.surfaceContainerHighest),
    };

IconData _iconFor(SchoolFile file) {
  final mime = file.mimeType.toLowerCase();
  if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.contains('audio')) return Icons.audiotrack_outlined;
  if (mime.contains('video')) return Icons.movie_outlined;
  if (mime.contains('sheet') || mime.contains('excel') || mime.contains('csv')) {
    return Icons.table_chart_outlined;
  }
  if (mime.contains('word') || mime.contains('document') || mime.contains('text')) {
    return Icons.description_outlined;
  }
  return switch (file.type) {
    'image' => Icons.image_outlined,
    'audio' => Icons.audiotrack_outlined,
    'video' => Icons.movie_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

String _prettyFilter(String value) {
  final text = value.replaceAll('_', ' ');
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

/// Human byte size; `null` sizes render as an em dash rather than "0 B".
String _formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final text = unit == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

String _formatStamp(DateTime? value) {
  if (value == null) return 'date unknown';
  final d = value.toLocal();
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// RLS hides these files from roles without school-file access; say so rather
/// than implying the school has no files.
String _describeFileError(PostgrestException e) {
  final raw = e.message.trim();
  final lower = raw.toLowerCase();
  if (lower.contains('row-level security')) {
    return 'Your role cannot read this school\'s files. Ask a principal or school admin.';
  }
  if (lower.contains('insufficient_permissions')) {
    return 'Your role cannot read this school\'s files.';
  }
  if (raw.isNotEmpty && raw.length <= 160) return raw;
  return 'The school files could not be loaded. Try again.';
}