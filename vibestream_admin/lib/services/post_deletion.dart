// lib/services/post_deletion.dart
//
// Requires in pubspec.yaml:  firebase_storage: ^<same major as your other firebase packages>

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

bool _isFirebaseStorageUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host.contains('firebasestorage.googleapis.com') ||
      host.contains('firebasestorage.app') ||
      host == 'storage.googleapis.com';
}

/// Permanently deletes a post from Firebase:
///  1. media files in Firebase Storage (only URLs that really are Storage URLs)
///  2. the post's `comments` subcollection
///  3. the post document itself (deleted LAST so you can retry if a step fails)
///
/// NOTE: files hosted on Cloudinary (the `media[].url` / `publicId` values)
/// are NOT deleted by this function. Cloudinary deletion needs your API secret,
/// so it has to be done from a Cloud Function / backend, never from the app.
/// Base64 images (base64Data) live inside the document and go with step 3.
Future<void> permanentlyDeletePost(String postId) async {
  final db = FirebaseFirestore.instance;
  final postRef = db.collection('posts').doc(postId);

  final snap = await postRef.get();
  final data = snap.data() ?? <String, dynamic>{};

  // 1. Firebase Storage files ---------------------------------------------
  final urls = <String>{};

  void addUrl(dynamic v) {
    if (v is String && v.startsWith('http') && _isFirebaseStorageUrl(v)) {
      urls.add(v);
    }
  }

  addUrl(data['mediaUrl']);
  addUrl(data['thumbnailUrl']);

  final media = data['media'];
  if (media is List) {
    for (final item in media) {
      if (item is Map) {
        addUrl(item['url']);
        addUrl(item['thumbnailUrl']);
      } else {
        addUrl(item);
      }
    }
  }

  for (final url in urls) {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } on FirebaseException catch (e) {
      // Already gone -> fine. Anything else -> surface it.
      if (e.code != 'object-not-found') rethrow;
    }
  }

  // 2. Subcollections ------------------------------------------------------
  await _deleteCollection(postRef.collection('comments'));

  // 3. The post document ---------------------------------------------------
  await postRef.delete();
}

Future<void> _deleteCollection(
  CollectionReference<Map<String, dynamic>> col,
) async {
  while (true) {
    final batchSnap = await col.limit(200).get();
    if (batchSnap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final d in batchSnap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}

/// Shows a confirmation dialog, then deletes. Returns true if the post was deleted.
Future<bool> confirmAndDeletePost(BuildContext context, String postId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete post permanently?'),
      content: const Text(
        'This removes the post and its comments from Firebase. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete forever'),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  try {
    await permanentlyDeletePost(postId);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post deleted permanently')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete post: $e')));
    }
    return false;
  }
}
