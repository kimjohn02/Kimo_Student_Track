import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/user_model.dart' as app_models;
import 'storage_service.dart';

class SupabaseAuthService extends ChangeNotifier {
  SupabaseClient get _client => SupabaseConfig.client;

  User? get supabaseUser => _client.auth.currentUser;
  dynamic get firebaseUser => supabaseUser; // Backward compatibility

  app_models.User? appUser;
  String? _initError;
  String? get initError => _initError;
  String? _loadingUid;

  final StorageService _storageService = StorageService();

  SupabaseAuthService() {
    _initAuthListener();
  }

  void _initAuthListener() {
    try {
      _client.auth.onAuthStateChange.listen(
        (data) async {
          final user = data.session?.user;
          if (user != null) {
            if (_loadingUid == user.id) return;
            try {
              await _loadAppUser(user.id);
            } catch (e) {
              debugPrint('Error loading user profile on auth state change: $e');
            }
          } else {
            appUser = null;
          }
          notifyListeners();
        },
        onError: (error) {
          _initError = 'Supabase auth listener error: $error';
          notifyListeners();
        },
      );

      // If already logged in on cold start
      final initialUser = _client.auth.currentUser;
      if (initialUser != null) {
        _loadAppUser(initialUser.id);
      }
    } catch (e) {
      _initError = 'SupabaseAuthService init failed: $e';
      notifyListeners();
    }
  }

  /// Load user profile from Supabase 'profiles' table
  Future<void> _loadAppUser(String uid) async {
    _loadingUid = uid;
    try {
      final doc = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (doc != null) {
        appUser = app_models.User.fromJson(doc);
      } else {
        // Create initial record if missing
        final currentAuthUser = _client.auth.currentUser;
        final email = currentAuthUser?.email ?? '';
        final name = (currentAuthUser?.userMetadata?['name'] ??
                email.split('@').first)
            .toString();

        final u = app_models.User(
          id: uid,
          email: email,
          name: name,
          role: 'user',
          points: 0,
          isApproved: true,
        );

        await _client.from('profiles').upsert(u.toSupabaseMap());
        appUser = u;
      }

      // Check account status
      if (appUser != null) {
        if (appUser!.isBanned) {
          await signOut();
          throw 'This account is under investigation. Please contact admin@keitask.com.';
        }
        if (appUser!.role == 'professor' && !appUser!.isApproved) {
          await signOut();
          throw 'Your professor account is pending approval. Please contact admin@keitask.com.';
        }
      }
    } finally {
      _loadingUid = null;
      notifyListeners();
    }
  }

  /// Upload an image to Cloudinary and return the secure URL
  Future<String?> uploadProfileImageToCloudinary(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    return await _storageService.uploadImage(file, onProgress: onProgress);
  }

  /// Register a new user using Supabase Auth + Cloudinary avatar upload
  Future<app_models.User?> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    String role = 'user',
    File? profileImageFile,
  }) async {
    String? photoUrl;
    if (profileImageFile != null) {
      try {
        photoUrl = await uploadProfileImageToCloudinary(profileImageFile);
      } catch (e) {
        debugPrint('Profile image upload to Cloudinary failed: $e');
      }
    }

    final AuthResponse res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'name': name,
        'role': role,
        if (photoUrl != null) 'profile_image': photoUrl,
      },
    );

    final user = res.user;
    if (user == null) {
      throw 'Registration failed. Please check your credentials.';
    }

    final isApproved = role != 'professor';
    final userRecord = app_models.User(
      id: user.id,
      email: email,
      name: name,
      role: role,
      profileImage: photoUrl,
      isApproved: isApproved,
    );

    await _client.from('profiles').upsert(userRecord.toSupabaseMap());
    appUser = userRecord;
    notifyListeners();
    return appUser;
  }

  /// Log in with email and password via Supabase Auth
  Future<app_models.User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final AuthResponse res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = res.user;
    if (user == null) {
      throw 'Login failed. Invalid email or password.';
    }

    await _loadAppUser(user.id);
    notifyListeners();
    return appUser;
  }

  /// Sign in using Google OAuth with Supabase
  Future<app_models.User?> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.keitask://login-callback/',
      );
      return appUser;
    } catch (e) {
      debugPrint('Google Sign-in error: $e');
      rethrow;
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    await _client.auth.signOut();
    appUser = null;
    notifyListeners();
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  /// Update user display name in Supabase Auth & Profiles table
  Future<void> updateUserName(String newName) async {
    final user = supabaseUser;
    if (user == null) return;

    await _client.auth.updateUser(
      UserAttributes(data: {'name': newName}),
    );

    await _client.from('profiles').update({
      'name': newName,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id);

    if (appUser != null) {
      appUser = app_models.User(
        id: appUser!.id,
        email: appUser!.email,
        name: newName,
        role: appUser!.role,
        profileImage: appUser!.profileImage,
        points: appUser!.points,
        isApproved: appUser!.isApproved,
        phoneNumber: appUser!.phoneNumber,
        isBanned: appUser!.isBanned,
        notificationsEnabled: appUser!.notificationsEnabled,
      );
      notifyListeners();
    }
  }

  /// Update user profile image URL (Cloudinary URL)
  Future<void> updateUserProfileImage(String imageUrl) async {
    final user = supabaseUser;
    if (user == null) return;

    await _client.from('profiles').update({
      'profile_image': imageUrl,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id);

    if (appUser != null) {
      appUser = app_models.User(
        id: appUser!.id,
        email: appUser!.email,
        name: appUser!.name,
        role: appUser!.role,
        profileImage: imageUrl,
        points: appUser!.points,
        isApproved: appUser!.isApproved,
        phoneNumber: appUser!.phoneNumber,
        isBanned: appUser!.isBanned,
        notificationsEnabled: appUser!.notificationsEnabled,
      );
      notifyListeners();
    }
  }

  /// Update user phone number
  Future<void> updateUserPhone(String phoneNumber) async {
    final user = supabaseUser;
    if (user == null) return;

    await _client.from('profiles').update({
      'phone_number': phoneNumber,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id);

    if (appUser != null) {
      appUser = app_models.User(
        id: appUser!.id,
        email: appUser!.email,
        name: appUser!.name,
        role: appUser!.role,
        profileImage: appUser!.profileImage,
        points: appUser!.points,
        isApproved: appUser!.isApproved,
        phoneNumber: phoneNumber,
        isBanned: appUser!.isBanned,
        notificationsEnabled: appUser!.notificationsEnabled,
      );
      notifyListeners();
    }
  }

  /// Change password
  Future<void> changePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Update notification preferences
  Future<void> updateNotificationPreference(bool enabled) async {
    final user = supabaseUser;
    if (user == null) return;

    await _client.from('profiles').update({
      'notifications_enabled': enabled,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id);

    if (appUser != null) {
      appUser = app_models.User(
        id: appUser!.id,
        email: appUser!.email,
        name: appUser!.name,
        role: appUser!.role,
        profileImage: appUser!.profileImage,
        points: appUser!.points,
        isApproved: appUser!.isApproved,
        phoneNumber: appUser!.phoneNumber,
        isBanned: appUser!.isBanned,
        notificationsEnabled: enabled,
      );
      notifyListeners();
    }
  }

  /// Increment user points
  Future<void> incrementUserPoints(String uid, int by) async {
    final doc = await _client.from('profiles').select('points').eq('id', uid).maybeSingle();
    final currentPoints = (doc?['points'] as num?)?.toInt() ?? 0;
    final newPoints = currentPoints + by;

    await _client.from('profiles').update({
      'points': newPoints,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);

    if (appUser != null && appUser!.id == uid) {
      appUser = app_models.User(
        id: appUser!.id,
        email: appUser!.email,
        name: appUser!.name,
        role: appUser!.role,
        profileImage: appUser!.profileImage,
        points: newPoints,
        isApproved: appUser!.isApproved,
      );
      notifyListeners();
    }
  }

  /// Reload current user profile from database
  Future<void> reloadCurrentUser() async {
    final user = supabaseUser;
    if (user != null) {
      await _loadAppUser(user.id);
      notifyListeners();
    }
  }

  // --- ADMIN AND LEADERBOARD OPERATIONS ---

  /// Realtime stream of all user profiles
  Stream<List<app_models.User>> usersStream() {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .map((dataList) => dataList.map((d) => app_models.User.fromJson(d)).toList());
  }

  /// Realtime stream of all users for leaderboard (ordered by points desc)
  Stream<List<app_models.User>> getAllUsersStream() {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .order('points', ascending: false)
        .map((dataList) => dataList.map((d) => app_models.User.fromJson(d)).toList());
  }

  /// Fetch all users once
  Future<List<app_models.User>> getAllUsers() async {
    final res = await _client.from('profiles').select().order('points', ascending: false);
    return (res as List<dynamic>)
        .map((d) => app_models.User.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  /// Admin: update user role
  Future<void> updateUserRole(String uid, String role) async {
    await _client.from('profiles').update({
      'role': role,
      'is_approved': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);

    if (appUser?.id == uid) {
      await reloadCurrentUser();
    }
  }

  /// Admin: approve user
  Future<void> approveUser(String uid) async {
    await updateUserApproval(uid, true);
  }

  /// Admin: toggle approval
  Future<void> updateUserApproval(String uid, bool isApproved) async {
    await _client.from('profiles').update({
      'is_approved': isApproved,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);

    if (appUser?.id == uid) {
      await reloadCurrentUser();
    }
  }

  /// Admin: ban / unban user
  Future<void> banUser(String uid, bool isBanned) async {
    await _client.from('profiles').update({
      'is_banned': isBanned,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);

    if (appUser?.id == uid) {
      if (isBanned) {
        await signOut();
      } else {
        await reloadCurrentUser();
      }
    }
  }

  Future<void> updateCurrentUserRole(String role) async {
    final user = supabaseUser;
    if (user != null) {
      await updateUserRole(user.id, role);
    }
  }
}
