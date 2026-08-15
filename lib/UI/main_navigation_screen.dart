import 'package:firebase_auth/firebase_auth.dart';
import 'package:first_app/UI/add_post_screen.dart';
import 'package:first_app/UI/friends_screen.dart';
import 'package:first_app/UI/home_chats_screen.dart';
import 'package:first_app/UI/newsfeed_screen.dart';
import 'package:first_app/UI/user_profile_screen.dart';
import 'package:flutter/material.dart';

/// Persistent shell that owns the bottom navigation bar. Home, Explore,
/// Chats, and Profile all live inside an [IndexedStack] here so switching
/// tabs never pushes a new route — the bar stays visible on every tab,
/// and each tab keeps its own scroll position / state when you switch away
/// and back.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  // Index into _tabs (4 entries: Home, Explore, Chats, Profile).
  int _currentIndex = 0;

  final _tabs = const [
    NewsfeedScreen(),
    FriendsScreen(),
    HomeChatsScreen(),
    _ProfileTab(),
  ];

  Future<void> _openAddPost() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddPostScreen()),
    );
  }

  // The bottom bar has 5 buttons (Home, Explore, +, Chats, Profile) but
  // only 4 are real tabs — the "+" is a one-off modal push. This maps
  // between the two.
  void _onNavButtonTapped(int buttonIndex) {
    if (buttonIndex == 2) {
      _openAddPost();
      return;
    }
    final tabIndex = buttonIndex < 2 ? buttonIndex : buttonIndex - 1;
    setState(() => _currentIndex = tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: _buildBottomNav(colorScheme),
    );
  }

  Widget _buildBottomNav(ColorScheme colorScheme) {
    final selectedButtonIndex =
        _currentIndex < 2 ? _currentIndex : _currentIndex + 1;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: selectedButtonIndex == 0,
                onTap: () => _onNavButtonTapped(0),
              ),
              _NavItem(
                icon: Icons.search_rounded,
                label: 'Explore',
                selected: selectedButtonIndex == 1,
                onTap: () => _onNavButtonTapped(1),
              ),
              _CreateNavButton(onTap: () => _onNavButtonTapped(2)),
              _NavItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chats',
                selected: selectedButtonIndex == 3,
                onTap: () => _onNavButtonTapped(3),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                selected: selectedButtonIndex == 4,
                onTap: () => _onNavButtonTapped(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resolves the signed-in user's own profile lazily so this file doesn't
/// need to know about auth state until the Profile tab is actually built.
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return UserProfileScreen(userId: uid);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _CreateNavButton extends StatelessWidget {
  const _CreateNavButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Transform.translate(
      offset: const Offset(0, -10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(Icons.add, color: colorScheme.onPrimary, size: 28),
        ),
      ),
    );
  }
}
