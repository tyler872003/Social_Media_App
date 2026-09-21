import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/admin_post.dart';
import '../services/firestore_admin_service.dart';
import '../theme/app_theme.dart';
import '../widgets/post_thumbnail.dart';

class ModerationQueueScreen extends StatefulWidget {
  /// When true, renders as bare content for the AdminShell
  /// (no Scaffold/AppBar).
  final bool embedded;

  /// Search text coming from the AdminShell top bar. Optional so the screen
  /// can still be pushed standalone (e.g. from the dashboard) without one.
  final ValueListenable<String>? searchQuery;

  const ModerationQueueScreen({
    super.key,
    this.embedded = false,
    this.searchQuery,
  });

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  final _service = FirestoreAdminService();

  /// Fallback used when no search query is supplied.
  static final ValueNotifier<String> _noSearch = ValueNotifier<String>('');

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pending reports')),
      body: content,
    );
  }

  Widget _buildContent() {
    return ValueListenableBuilder<String>(
      valueListenable: widget.searchQuery ?? _noSearch,
      builder: (context, rawQuery, _) {
        final query = rawQuery.trim();
        final q = query.toLowerCase();

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

            final allReports = snapshot.data!;

            // Filter by reason, post id, or report id.
            final reports = q.isEmpty
                ? allReports
                : allReports
                      .where(
                        (r) =>
                            r.reason.toLowerCase().contains(q) ||
                            r.postId.toLowerCase().contains(q) ||
                            r.id.toLowerCase().contains(q),
                      )
                      .toList();

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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        q.isNotEmpty
                            ? 'No reports match "$query".'
                            : 'No pending reports 🎉',
                      ),
                    )
                  else
                    ...reports.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),

                        // IMPORTANT:
                        // Give every report its own stable identity.
                        // This prevents Flutter from reusing the state
                        // of deleted report C for report D.
                        child: _ReportCard(
                          key: ValueKey(r.id),
                          report: r,
                          service: _service,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ReportCard extends StatefulWidget {
  final AdminReport report;
  final FirestoreAdminService service;

  const _ReportCard({super.key, required this.report, required this.service});

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
    _loadPost();
  }

  /// Loads the post associated with this report.
  ///
  /// The important part here is that the old post is cleared before
  /// loading the new one. This prevents stale post data from appearing
  /// when the moderation queue changes.
  Future<void> _loadPost() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _post = null;
      });
    }

    try {
      final post = await widget.service.getPost(widget.report.postId);

      if (!mounted) return;

      setState(() {
        _post = post;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _post = null;
        _loading = false;
      });
    }
  }

  /// Extra protection against Flutter reusing a State object.
  ///
  /// Normally ValueKey(report.id) prevents this from being necessary,
  /// but this makes the card robust if the report itself changes.
  @override
  void didUpdateWidget(covariant _ReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.report.id != widget.report.id ||
        oldWidget.report.postId != widget.report.postId) {
      _loadPost();
    }
  }

  Future<void> _remove() async {
    if (_acting) return;

    setState(() {
      _acting = true;
    });

    try {
      await widget.service.removePost(
        widget.report.postId,
        reason: widget.report.reason,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted successfully.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete post: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _acting = false;
        });
      }
    }
  }

  Future<void> _dismiss() async {
    if (_acting) return;

    setState(() {
      _acting = true;
    });

    try {
      await widget.service.dismissReport(widget.report.id);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report dismissed.')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to dismiss report: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _acting = false;
        });
      }
    }
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
        border: Border.all(color: AppColors.outlineVariant),
      ),

      // Clips the accent stripe and contents to the rounded card.
      clipBehavior: Clip.antiAlias,

      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: LinearProgressIndicator(),
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // High-priority accent stripe.
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
                          // ------------------------------------------------
                          // POST THUMBNAIL
                          // ------------------------------------------------
                          if (_post != null)
                            PostThumbnail(
                              media: _post!.media,
                              base64Data: _post!.imageBase64,
                              mediaUrl: _post!.mediaUrl,
                              thumbnailUrl: _post!.thumbnailUrl,
                              mediaType: _post!.mediaType,
                              size: 56,
                            ),

                          if (_post != null) const SizedBox(width: 14),

                          // ------------------------------------------------
                          // REPORT INFORMATION
                          // ------------------------------------------------
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

                          // ------------------------------------------------
                          // ACTION BUTTONS
                          // ------------------------------------------------
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
