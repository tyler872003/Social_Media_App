import 'package:flutter/material.dart';
import '../services/report_service.dart';

/// Drop this into your post's action menu (wherever the "..." / options
/// icon lives on a post card). Example:
///
///   IconButton(
///     icon: const Icon(Icons.more_vert),
///     onPressed: () => showReportPostSheet(context, postId: post.id),
///   )
///
/// or add it alongside like/comment icons as its own flag button:
///
///   ReportPostButton(postId: post.id)

Future<void> showReportPostSheet(
  BuildContext context, {
  required String postId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReportPostSheet(postId: postId),
  );
}

class ReportPostButton extends StatelessWidget {
  final String postId;
  const ReportPostButton({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.flag_outlined),
      tooltip: 'Report post',
      onPressed: () => showReportPostSheet(context, postId: postId),
    );
  }
}

class ReportPostSheet extends StatefulWidget {
  final String postId;
  const ReportPostSheet({super.key, required this.postId});

  @override
  State<ReportPostSheet> createState() => _ReportPostSheetState();
}

class _ReportPostSheetState extends State<ReportPostSheet> {
  final _service = ReportService();
  final _detailsController = TextEditingController();
  ReportReason? _selected;
  bool _submitting = false;
  String? _error;
  bool _submitted = false;

  Future<void> _submit() async {
    if (_selected == null) {
      setState(() => _error = 'Choose a reason first.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.reportPost(
        postId: widget.postId,
        reason: _selected!,
        details: _detailsController.text.trim().isEmpty
            ? null
            : _detailsController.text.trim(),
      );
      setState(() => _submitted = true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: _submitted ? _buildSubmitted(context) : _buildForm(context),
    );
  }

  Widget _buildSubmitted(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 12),
        const Text('Report submitted',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Thanks — our team will review this post.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Report post',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Why are you reporting this post?',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        ...ReportReason.values.map(
          (reason) => RadioListTile<ReportReason>(
            contentPadding: EdgeInsets.zero,
            title: Text(reason.label),
            value: reason,
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _detailsController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Additional details (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Submit report'),
          ),
        ),
      ],
    );
  }
}
