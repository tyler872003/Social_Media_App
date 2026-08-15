import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:first_app/services/friends_repository.dart';
import 'package:first_app/UI/user_profile_screen.dart';
import 'package:first_app/widgets/app_loading.dart';
import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friendsRepo = FriendsRepository();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<String> _myFriends = [];

  @override
  void initState() {
    super.initState();
    _loadMyFriends();
  }

  Future<void> _loadMyFriends() async {
    final friends = await _friendsRepo.getFriendsList();
    if (mounted) setState(() => _myFriends = friends);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildAvatar(String? photoUrl, double radius) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(
              base64Decode(photoUrl.split(',').last),
            ),
          );
        } catch (_) {}
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(photoUrl),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      child: Icon(Icons.person, size: radius),
    );
  }

  int _mutualFriendsCount(Map<String, dynamic> otherUserData) {
    final theirFriends = List<String>.from(otherUserData['friends'] ?? []);
    return theirFriends.where((f) => _myFriends.contains(f)).length;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Friends'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Find'),
              Tab(text: 'Requests'),
              Tab(text: 'My Friends'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFindTab(),
            _buildRequestsTab(),
            _buildMyFriendsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildFindTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            onChanged:
                (val) =>
                    setState(() => _searchQuery = val.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search users by name or email',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
        Expanded(
          child:
              _searchQuery.isEmpty
                  ? const Center(
                    child: Text('Search for people to add as friends.'),
                  )
                  : StreamBuilder<QuerySnapshot>(
                    stream:
                        FirebaseFirestore.instance
                            .collection('users')
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const AppLoadingScreen(
                          message: 'Searching users...',
                        );
                      }

                      final docs =
                          snapshot.data!.docs.where((doc) {
                            if (doc.id == _friendsRepo.currentUserId) {
                              return false;
                            }
                            final data = doc.data() as Map<String, dynamic>;
                            final name =
                                (data['displayName'] as String?)
                                    ?.toLowerCase() ??
                                '';
                            final email =
                                (data['email'] as String?)?.toLowerCase() ?? '';
                            return name.contains(_searchQuery) ||
                                email.contains(_searchQuery);
                          }).toList();

                      if (docs.isEmpty) {
                        return const Center(child: Text('No users found.'));
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;
                          final uid = docs[index].id;
                          final photoUrl = data['photoUrl'] as String?;
                          return ListTile(
                            leading: _buildAvatar(photoUrl, 20),
                            title: Text(data['displayName'] ?? 'User'),
                            subtitle: Text(data['email'] ?? ''),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => UserProfileScreen(userId: uid),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildRequestsTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _friendsRepo.receivedRequestsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AppLoadingScreen(message: 'Loading requests...');
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No friend requests.'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final requestUid = docs[index].data()['uid'] as String;
            return FutureBuilder<DocumentSnapshot>(
              future:
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(requestUid)
                      .get(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const ListTile(
                    title: AppLoadingIndicator(message: 'Loading...'),
                  );
                }
                if (!userSnap.hasData || !userSnap.data!.exists) {
                  return const SizedBox.shrink(); // skip ghost users
                }
                final data =
                    userSnap.data!.data() as Map<String, dynamic>? ?? {};
                final photoUrl = data['photoUrl'] as String?;
                final mutualCount = _mutualFriendsCount(data);

                return ListTile(
                  leading: _buildAvatar(photoUrl, 22),
                  title: Text(data['displayName'] ?? 'User'),
                  subtitle: Text(
                    mutualCount > 0
                        ? '$mutualCount mutual friend${mutualCount == 1 ? '' : 's'}'
                        : 'No mutual friends',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(userId: requestUid),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () async {
                          try {
                            await _friendsRepo.acceptFriendRequest(requestUid);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Friend accepted!')),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () async {
                          try {
                            await _friendsRepo.declineFriendRequest(requestUid);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Request declined.'),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMyFriendsTab() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _friendsRepo.currentUserStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AppLoadingScreen(message: 'Loading friends...');
        }
        final data = snapshot.data!.data() ?? {};
        final friends = List<String>.from(data['friends'] ?? []);

        if (friends.isEmpty) {
          return const Center(child: Text('You have no friends yet.'));
        }

        return ListView.builder(
          itemCount: friends.length,
          itemBuilder: (context, index) {
            final friendUid = friends[index];
            return FutureBuilder<DocumentSnapshot>(
              future:
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(friendUid)
                      .get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) {
                  return const ListTile(
                    title: AppLoadingIndicator(message: 'Loading...'),
                  );
                }
                final userData =
                    userSnap.data!.data() as Map<String, dynamic>? ?? {};
                final photoUrl = userData['photoUrl'] as String?;
                return ListTile(
                  leading: _buildAvatar(photoUrl, 20),
                  title: Text(userData['displayName'] ?? 'User'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(userId: friendUid),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove, color: Colors.red),
                    onPressed: () => _friendsRepo.removeFriend(friendUid),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
