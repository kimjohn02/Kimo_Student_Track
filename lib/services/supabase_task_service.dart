import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/user_model.dart' as app_models;

class SupabaseTaskService extends ChangeNotifier {
  SupabaseClient get _client => SupabaseConfig.client;

  /// Realtime stream of all tasks, sorted by creation date or due date
  Stream<List<app_models.Task>> tasksStream() {
    try {
      return _client
          .from('tasks')
          .stream(primaryKey: ['id'])
          .order('due_date', ascending: true)
          .map((dataList) => dataList.map((data) => app_models.Task.fromJson(data)).toList());
    } catch (e) {
      debugPrint('SupabaseTaskService tasksStream error: $e');
      return Stream.value(<app_models.Task>[]);
    }
  }

  /// Fetch all tasks from the Supabase database
  Future<List<app_models.Task>> getAllTasks() async {
    try {
      final response = await _client.from('tasks').select();
      final list = (response as List<dynamic>)
          .map((item) => app_models.Task.fromJson(item as Map<String, dynamic>))
          .toList();
      return list;
    } catch (e) {
      debugPrint('SupabaseTaskService getAllTasks error: $e');
      return [];
    }
  }

  /// Create a new task in Supabase
  Future<void> createTask(app_models.Task task) async {
    try {
      await _client.from('tasks').upsert(task.toSupabaseMap());
      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService createTask error: $e');
      rethrow;
    }
  }

  /// Update the status of a task
  Future<void> updateTaskStatus(String taskId, String newStatus) async {
    try {
      await _client.from('tasks').update({
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);
      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService updateTaskStatus error: $e');
      rethrow;
    }
  }

  /// Reject a task with a reason
  Future<void> rejectTask(String taskId, String reason) async {
    try {
      await _client.from('tasks').update({
        'status': 'rejected',
        'rejection_reason': reason,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);
      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService rejectTask error: $e');
      rethrow;
    }
  }

  /// Resubmit a rejected task
  Future<void> resubmitTask(String taskId) async {
    try {
      await _client.from('tasks').update({
        'status': 'resubmitted',
        'rejection_reason': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);
      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService resubmitTask error: $e');
      rethrow;
    }
  }

  /// Approve a student task
  Future<void> approveTask(String taskId) async {
    try {
      await _client.from('tasks').update({
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
        'rejection_reason': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);
      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService approveTask error: $e');
      rethrow;
    }
  }

  /// Approve a professor-created task
  Future<void> approveProfessorTask(String taskId) async {
    try {
      await _client.from('tasks').update({
        'status': 'assigned',
        'rejection_reason': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);
      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService approveProfessorTask error: $e');
      rethrow;
    }
  }

  /// Bookmark or unbookmark a task
  Future<void> toggleBookmark(String taskId, String userId, bool add) async {
    try {
      final taskDoc = await _client.from('tasks').select('bookmarked_by').eq('id', taskId).maybeSingle();
      if (taskDoc == null) return;

      List<dynamic> bookmarks = [];
      if (taskDoc['bookmarked_by'] is List) {
        bookmarks = List.from(taskDoc['bookmarked_by']);
      }

      if (add) {
        if (!bookmarks.contains(userId)) bookmarks.add(userId);
      } else {
        bookmarks.remove(userId);
      }

      await _client.from('tasks').update({
        'bookmarked_by': bookmarks,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);

      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService toggleBookmark error: $e');
      rethrow;
    }
  }

  /// Mark task as complete and award points
  Future<void> markTaskComplete(
    String taskId, {
    String? completedBy,
    int rewardPoints = 10,
  }) async {
    try {
      final taskDoc = await _client.from('tasks').select().eq('id', taskId).maybeSingle();
      if (taskDoc == null) return;

      final task = app_models.Task.fromJson(taskDoc);
      final completionStatus = Map<String, dynamic>.from(taskDoc['completion_status'] ?? {});

      if (completedBy != null && completedBy.isNotEmpty) {
        completionStatus[completedBy] = DateTime.now().toIso8601String();

        // Increment user points in profiles
        try {
          final profileDoc = await _client
              .from('profiles')
              .select('points')
              .eq('id', completedBy)
              .maybeSingle();
          if (profileDoc != null) {
            final currentPoints = (profileDoc['points'] as num?)?.toInt() ?? 0;
            await _client.from('profiles').update({
              'points': currentPoints + rewardPoints,
            }).eq('id', completedBy);
          }
        } catch (e) {
          debugPrint('Error awarding points: $e');
        }

        // Check if all assignees completed
        bool allCompleted = true;
        if (task.assignees.isNotEmpty) {
          for (var assignee in task.assignees) {
            if (!completionStatus.containsKey(assignee)) {
              allCompleted = false;
              break;
            }
          }
        }

        await _client.from('tasks').update({
          'completion_status': completionStatus,
          if (allCompleted) 'status': 'completed',
          if (allCompleted) 'completed_at': DateTime.now().toIso8601String(),
          if (allCompleted) 'rejection_reason': null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', taskId);
      } else {
        await _client.from('tasks').update({
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
          'rejection_reason': null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', taskId);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService markTaskComplete error: $e');
      rethrow;
    }
  }

  /// Submit a task with Cloudinary file URLs
  Future<void> submitTask(
    String taskId,
    String userId,
    List<String> fileUrls,
  ) async {
    try {
      final taskDoc = await _client.from('tasks').select().eq('id', taskId).maybeSingle();
      if (taskDoc == null) return;

      final currentSubmissions = Map<String, dynamic>.from(taskDoc['submissions'] ?? {});
      currentSubmissions[userId] = fileUrls;

      final currentCompletion = Map<String, dynamic>.from(taskDoc['completion_status'] ?? {});
      currentCompletion[userId] = DateTime.now().toIso8601String();

      await _client.from('tasks').update({
        'submissions': currentSubmissions,
        'completion_status': currentCompletion,
        'status': 'pending', // Pending professor / admin review
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);

      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService submitTask error: $e');
      rethrow;
    }
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    try {
      await _client.from('tasks').delete().eq('id', taskId);
      notifyListeners();
    } catch (e) {
      debugPrint('SupabaseTaskService deleteTask error: $e');
      rethrow;
    }
  }
}
