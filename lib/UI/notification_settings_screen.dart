import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:first_app/services/notification_repository.dart';
import 'package:flutter/material.dart';

/// Full-page notification settings screen. Accessible from the home app bar.
///
/// Shows:
/// - Global toggles: Messages, Stories, Mentions
/// - List of currently muted chats with their mute-until times
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = NotificationRepository();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          'Notifications',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
        stream: repo.settingsStream(),
        builder: (context, snapshot) {
          // Merge with defaults so toggles show correctly before doc exists
          final raw = snapshot.data?.data() ?? {};
          final defaults = NotificationRepository.defaults();
          final settings = {...defaults, ...raw};

          final notifyMessages = settings['notifyMessages'] as bool? ?? true;
          final notifyStories = settings['notifyStories'] as bool? ?? true;
          final notifyMentions = settings['notifyMentions'] as bool? ?? true;
          final mutedChats =
              settings['mutedChats'] as Map<String, dynamic>? ?? {};

          // Filter out expired mutes for the list display
          final now = DateTime.now().millisecondsSinceEpoch;
          final activeMutes =
              mutedChats.entries.where((e) {
                final v = e.value;
                if (v == -1) return true;
                if (v is int) return v > now;
                return false;
              }).toList();

          return ListView(
            children: [
              // ── Global toggles ───────────────────────────────────────────
              const _SectionHeader(title: 'Notify me about'),

              _ToggleTile(
                icon: Icons.chat_bubble_outline,
                title: 'Messages',
                subtitle: 'New messages in direct chats',
                value: notifyMessages,
                onChanged: (v) => repo.setNotifyMessages(v),
              ),

              _ToggleTile(
                icon: Icons.auto_stories_outlined,
                title: 'Stories',
                subtitle: 'When someone posts a new story',
                value: notifyStories,
                onChanged: (v) => repo.setNotifyStories(v),
              ),

              _ToggleTile(
                icon: Icons.alternate_email,
                title: 'Group Mentions',
                subtitle: 'When someone mentions you in a group',
                value: notifyMentions,
                onChanged: (v) => repo.setNotifyMentions(v),
              ),

              const Divider(height: 32),

              // ── Muted chats ──────────────────────────────────────────────
              const _SectionHeader(title: 'Muted chats'),

              if (activeMutes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    'No muted chats. Long-press a chat or use the ⋮ menu inside a chat to mute.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...activeMutes.map((entry) {
                  final chatId = entry.key;
                  final label =
                      repo.muteStatusLabel(settings, chatId) ?? 'Muted';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.notifications_off_outlined,
                        color: colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      // Show shortened chatId — in a real app you'd resolve
                      // the chat name here; see note below
                      _shortChatId(chatId),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await repo.unmuteChat(chatId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Chat unmuted'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Unmute',
                        style: TextStyle(color: Colors.blueAccent),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// Shows first 8 chars of chatId until you wire in real chat names.
  String _shortChatId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}…';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SwitchListTile(
      secondary: CircleAvatar(
        backgroundColor:
            value
                ? Colors.blueAccent.withValues(alpha: 0.1)
                : colorScheme.surfaceContainerHighest,
        child: Icon(
          icon,
          color: value ? Colors.blueAccent : colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
      ),
      value: value,
      activeThumbColor: Colors.blueAccent,
      onChanged: onChanged,
    );
  }
}
