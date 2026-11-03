import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/app_user.dart';
import '../models/post.dart';

/// Thrown when an action is no longer allowed, e.g. another collector
/// reserved the post first.
class PostActionException implements Exception {
  PostActionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PostService {
  PostService({FirebaseFirestore? db, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  Stream<List<RecyclablePost>> _list(Query<Map<String, dynamic>> q) =>
      q.snapshots().map((s) {
        final posts = s.docs.map(RecyclablePost.fromDoc).toList();
        posts.sort((a, b) => (b.createdAt ?? DateTime.now())
            .compareTo(a.createdAt ?? DateTime.now()));
        return posts;
      });

  Stream<RecyclablePost?> watch(String id) => _posts
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? RecyclablePost.fromDoc(d) : null);

  Stream<List<RecyclablePost>> householdPosts(String uid) =>
      _list(_posts.where('householdId', isEqualTo: uid));

  /// Everything a collector can see on the map: available posts.
  Stream<List<RecyclablePost>> availablePosts() =>
      _list(_posts.where('status', isEqualTo: PostStatus.available.name));

  Stream<List<RecyclablePost>> reservedBy(String collectorId) => _list(_posts
      .where('reservedBy', isEqualTo: collectorId)
      .where('status', isEqualTo: PostStatus.reserved.name));

  Future<void> create({
    required AppUser household,
    required File photo,
    required List<RecyclableType> types,
    required String amount,
    required LatLng location,
    required String barangay,
    required PostLabel label,
    String notes = '',
  }) async {
    if (!isInsideTagum(location)) {
      throw PostActionException('The pin must be inside Tagum City.');
    }
    final doc = _posts.doc();
    final ref = _storage.ref('post_photos/${household.uid}/${doc.id}.jpg');
    await ref.putFile(photo, SettableMetadata(contentType: 'image/jpeg'));
    final photoUrl = await ref.getDownloadURL();

    await doc.set({
      'householdId': household.uid,
      'householdName': household.name,
      'householdPhone': household.phone,
      'photoUrl': photoUrl,
      'types': types.map((t) => t.name).toList(),
      'amount': amount.trim(),
      'location': GeoPoint(location.latitude, location.longitude),
      'barangay': barangay,
      'label': label.name,
      'notes': notes.trim(),
      'status': PostStatus.available.name,
      'reservedBy': null,
      'reservedByName': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Household removes its own post (only while nobody has reserved it).
  Future<void> delete(RecyclablePost post) async {
    if (post.status != PostStatus.available) {
      throw PostActionException(
          'A collector already reserved this. Ask them to cancel first.');
    }
    await _posts.doc(post.id).delete();
    try {
      await _storage.refFromURL(post.photoUrl).delete();
    } catch (_) {
      // Photo cleanup is best-effort.
    }
  }

  /// Reserve inside a transaction so two collectors can't both get it.
  Future<void> reserve(String postId, AppUser collector) =>
      _db.runTransaction((tx) async {
        final ref = _posts.doc(postId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw PostActionException('This post was removed.');
        if (snap.data()!['status'] != PostStatus.available.name) {
          throw PostActionException(
              'Sorry, another collector already reserved this.');
        }
        tx.update(ref, {
          'status': PostStatus.reserved.name,
          'reservedBy': collector.uid,
          'reservedByName': collector.name,
          'reservedAt': FieldValue.serverTimestamp(),
        });
      });

  Future<void> cancelReservation(String postId, String collectorId) =>
      _db.runTransaction((tx) async {
        final ref = _posts.doc(postId);
        final snap = await tx.get(ref);
        final d = snap.data();
        if (d == null ||
            d['status'] != PostStatus.reserved.name ||
            d['reservedBy'] != collectorId) {
          throw PostActionException('You can no longer cancel this.');
        }
        tx.update(ref, {
          'status': PostStatus.available.name,
          'reservedBy': null,
          'reservedByName': null,
          'reservedAt': null,
        });
      });

  Future<void> markCollected(String postId, String collectorId) =>
      _db.runTransaction((tx) async {
        final ref = _posts.doc(postId);
        final snap = await tx.get(ref);
        final d = snap.data();
        if (d == null ||
            d['status'] != PostStatus.reserved.name ||
            d['reservedBy'] != collectorId) {
          throw PostActionException('Only the collector who reserved this can mark it collected.');
        }
        tx.update(ref, {
          'status': PostStatus.collected.name,
          'collectedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Household rates the collector once, after pickup.
  Future<void> rateCollector(RecyclablePost post, int stars) =>
      _db.runTransaction((tx) async {
        final postRef = _posts.doc(post.id);
        final snap = await tx.get(postRef);
        final d = snap.data();
        if (d == null || d['status'] != PostStatus.collected.name) {
          throw PostActionException('You can rate only after pickup.');
        }
        if (d['rating'] != null) {
          throw PostActionException('You already rated this pickup.');
        }
        final collectorId = d['reservedBy'] as String;
        tx.update(postRef, {'rating': stars});
        tx.update(_db.collection('users').doc(collectorId), {
          'ratingSum': FieldValue.increment(stars),
          'ratingCount': FieldValue.increment(1),
        });
      });
}
