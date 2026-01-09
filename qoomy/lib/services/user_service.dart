import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qoomy/models/user_model.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  Future<UserModel?> getUser(String odId) async {
    final doc = await _usersCollection.doc(odId).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Stream<UserModel?> userStream(String odId) {
    return _usersCollection.doc(odId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    });
  }

  Future<void> updateUser(String odId, Map<String, dynamic> data) async {
    await _usersCollection.doc(odId).update(data);
  }

  Future<void> updateDisplayName(String odId, String displayName) async {
    await _usersCollection.doc(odId).update({'displayName': displayName});
  }

  Future<void> incrementGamesPlayed(String odId) async {
    await _usersCollection.doc(odId).update({
      'gamesPlayed': FieldValue.increment(1),
    });
  }

  Future<void> incrementGamesWon(String odId) async {
    await _usersCollection.doc(odId).update({
      'gamesWon': FieldValue.increment(1),
    });
  }

  Future<void> addScore(String odId, int score) async {
    await _usersCollection.doc(odId).update({
      'totalScore': FieldValue.increment(score),
    });
  }

  Future<void> updateStats(String odId, int score, bool isWinner) async {
    final updates = <String, dynamic>{
      'gamesPlayed': FieldValue.increment(1),
      'totalScore': FieldValue.increment(score),
    };

    if (isWinner) {
      updates['gamesWon'] = FieldValue.increment(1);
    }

    await _usersCollection.doc(odId).update(updates);
  }
}
