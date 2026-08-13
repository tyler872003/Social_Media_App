import 'package:flutter/material.dart';
import '../models/admin_post.dart';
import '../services/firestore_admin_service.dart';
import '../theme/app_theme.dart';
import '../widgets/post_thumbnail.dart';

class ModerationQueueScreen extends StatefulWidget {
  /// When true, renders as bare content for the AdminShell (no Scaffold/AppBar).
  final bool embedded;

  const ModerationQueueScreen({super.key, this.embedded = false});

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  final _service = FirestoreAdminService();

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Pending reports')),
      body: content,
    );
  }

  Widget _buildContent() {
    return StreamBuilder<List<AdminReport>>(
      stream: _service.pendingReportsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Error loading reports:\n\n${snapshot.error}',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final reports = snapshot.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Moderation Queue',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Review and manage reported content.',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (reports.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No pending reports 🎉'),
                )
              else
                ...reports.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ReportCard(report: r, service: _service),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportCard extends StatefulWidget {
  final AdminReport report;
  final FirestoreAdminService service;

  const _ReportCard({required this.report, required this.service});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  AdminPost? _post;
  bool _loading = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    widget.service.getPost(widget.report.postId).then((p) {
      if (mounted) {
        setState(() {
          _post = p;
          _loading = false;
        });
      }
    });
  }

  Future<void> _remove() async {
    setState(() => _acting = true);
    await widget.service.removePost(
      widget.report.postId,
      reason: widget.report.reason,
    );
    if (mounted) setState(() => _acting = false);
  }

  Future<void> _dismiss() async {
    setState(() => _acting = true);
    await widget.service.dismissReport(widget.report.id);
    if (mounted) setState(() => _acting = false);
  }

  ({Color bg, Color fg}) _tagColors(String reason) {
    final r = reason.toLowerCase();
    if (r.contains('spam')) {
      return (bg: const Color(0xFFFFE3D3), fg: const Color(0xFF8A4A00));
    }
    if (r.contains('harass')) {
      return (bg: AppColors.secondary, fg: Colors.white);
    }
    if (r.contains('media') || r.contains('inappropriate')) {
      return (
        bg: AppColors.primary.withValues(alpha: 0.12),
        fg: AppColors.primary,
      );
    }
    return (bg: AppColors.surfaceContainerHigh, fg: AppColors.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) {
    final tagColors = _tagColors(widget.report.reason);
    final isHighPriority = widget.report.reason.toLowerCase().contains(
      'harass',
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        // Must be a single uniform color — BoxDecoration can't paint a
        // borderRadius on a border whose sides have different colors.
        border: Border.all(color: AppColors.outlineVariant),
      ),
      // Clips the accent stripe below to the card's rounded corners.
      clipBehavior: Clip.antiAlias,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: LinearProgressIndicator(),
            )
          // IntrinsicHeight gives the Row below a finite height to measure
          // against, so CrossAxisAlignment.stretch has something concrete
          // to stretch to (this widget sits inside an unbounded-height
          // scroll context, so without it stretch tries to expand to
          // infinity and layout fails).
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left accent stripe, drawn as its own flat-colored
                  // strip rather than a border side.
                  Container(
                    width: 4,
                    color: isHighPriority
                        ? AppColors.secondary
                        : Colors.transparent,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_post != null)
                            PostThumbnail(
                              base64Data: _post!.imageBase64,
                              size: 56,
                            ),
                          if (_post != null) const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tagColors.bg,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        widget.report.reason.toUpperCase(),
                                        style: TextStyle(
                                          color: tagColors.fg,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _post == null
                                            ? '(post no longer exists)'
                                            : 'Reported post',
                                        style: const TextStyle(
                                          color: AppColors.onSurfaceVariant,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_post?.caption != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '"${_post!.caption}"',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_acting)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: _dismiss,
                                  child: const Text('Keep'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _post == null ? null : _remove,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.secondary,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
