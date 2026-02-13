import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qoomy/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Secure storage for persisting userId as fallback auth (Samsung S25 workaround)
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _userIdKey = 'qoomy_auth_user_id';
  static const _userEmailKey = 'qoomy_auth_user_email';

  // iOS requires the client ID from GoogleService-Info.plist
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: !kIsWeb && Platform.isIOS
        ? '338120090374-cmv8if92s6l3ol4f4evvjhocgf5c7a60.apps.googleusercontent.com'
        : null,
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Store userId in secure storage after successful sign-in
  Future<void> _persistUserToSecureStorage(User user) async {
    if (kIsWeb) return;
    await _secureStorage.write(key: _userIdKey, value: user.uid);
    await _secureStorage.write(key: _userEmailKey, value: user.email ?? '');
  }

  /// Clear secure storage on sign-out
  Future<void> _clearSecureStorage() async {
    if (kIsWeb) return;
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _userEmailKey);
  }

  /// Read stored userId from secure storage (for fallback re-auth)
  static Future<String?> getStoredUserId() async {
    if (kIsWeb) return null;
    return _secureStorage.read(key: _userIdKey);
  }

  /// Read stored email from secure storage (for diagnostics)
  static Future<String?> getStoredEmail() async {
    if (kIsWeb) return null;
    return _secureStorage.read(key: _userEmailKey);
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Ensure user document exists (for users created before this check was added)
    final userDoc = await _firestore
        .collection('users')
        .doc(userCredential.user!.uid)
        .get();

    if (!userDoc.exists) {
      await _createUserDocument(
        userCredential.user!.uid,
        userCredential.user!.email ?? email,
        userCredential.user!.displayName ?? 'Player',
      );
    }

    await _persistUserToSecureStorage(userCredential.user!);
    return userCredential;
  }

  Future<UserCredential> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await credential.user?.updateDisplayName(displayName);

    await _createUserDocument(
      credential.user!.uid,
      email,
      displayName,
    );

    await _persistUserToSecureStorage(credential.user!);
    return credential;
  }

  Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);

    final userDoc = await _firestore
        .collection('users')
        .doc(userCredential.user!.uid)
        .get();

    if (!userDoc.exists) {
      await _createUserDocument(
        userCredential.user!.uid,
        userCredential.user!.email ?? '',
        userCredential.user!.displayName ?? 'Player',
      );
    }

    await _persistUserToSecureStorage(userCredential.user!);
    return userCredential;
  }

  /// Generates a cryptographically secure random nonce
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// Returns the sha256 hash of [input] in hex notation
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<UserCredential?> signInWithApple() async {
    if (kIsWeb) {
      return _signInWithAppleWeb();
    } else {
      return _signInWithAppleNative();
    }
  }

  Future<UserCredential?> _signInWithAppleWeb() async {
    // Create an Apple auth provider
    final provider = OAuthProvider('apple.com');
    provider.addScope('email');
    provider.addScope('name');

    // Sign in with popup on web
    final userCredential = await _auth.signInWithPopup(provider);

    // Check if user document exists, create if not
    final userDoc = await _firestore
        .collection('users')
        .doc(userCredential.user!.uid)
        .get();

    if (!userDoc.exists) {
      await _createUserDocument(
        userCredential.user!.uid,
        userCredential.user!.email ?? '',
        userCredential.user!.displayName ?? 'Player',
      );
    }

    await _persistUserToSecureStorage(userCredential.user!);
    return userCredential;
  }

  Future<UserCredential?> _signInWithAppleNative() async {
    // Generate nonce for security
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    // Request credentials from Apple (native iOS - no webAuthenticationOptions needed)
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    // Create OAuth credential
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
      rawNonce: rawNonce,
    );

    // Sign in with Firebase
    final userCredential = await _auth.signInWithCredential(oauthCredential);

    // Check if user document exists, create if not
    final userDoc = await _firestore
        .collection('users')
        .doc(userCredential.user!.uid)
        .get();

    if (!userDoc.exists) {
      // Apple may not return name after first sign-in, so handle null
      String displayName = 'Player';
      if (appleCredential.givenName != null) {
        displayName = appleCredential.givenName!;
        if (appleCredential.familyName != null) {
          displayName += ' ${appleCredential.familyName}';
        }
      } else if (userCredential.user!.displayName != null) {
        displayName = userCredential.user!.displayName!;
      }

      await _createUserDocument(
        userCredential.user!.uid,
        userCredential.user!.email ?? '',
        displayName,
      );

      // Update Firebase user display name if we got it from Apple
      if (appleCredential.givenName != null) {
        await userCredential.user!.updateDisplayName(displayName);
      }
    }

    await _persistUserToSecureStorage(userCredential.user!);
    return userCredential;
  }

  Future<void> _createUserDocument(
    String odId,
    String email,
    String displayName,
  ) async {
    final user = UserModel(
      id: odId,
      email: email,
      displayName: displayName,
      createdAt: DateTime.now(),
    );

    await _firestore.collection('users').doc(odId).set(user.toFirestore());
  }

  Future<void> signOut() async {
    await _clearSecureStorage();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}
