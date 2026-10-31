// lib/models/user_model.dart
import 'grade_model.dart';

class User {
  final String id;
  final String email;
  final String name;
  final String role; // 'user', 'student', 'professor', 'admin'
  final String? profileImage;
  final int points; // Points used for leaderboard/rewards
  final bool isApproved; // For professors requiring admin approval

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.profileImage,
    this.points = 0,
    this.isApproved = true, // Default to true for students/users
    this.enrolledCourseIds,
    this.teachingCourseIds,
    this.phoneNumber,
    this.isBanned = false,
    this.notificationsEnabled,
  });

  final List<String>? enrolledCourseIds; // For students
  final List<String>? teachingCourseIds; // For professors
  final String? phoneNumber;
  final bool isBanned;
  final bool? notificationsEnabled;

  String get rank {
    if (points >= 5000) return 'Diamond';
    if (points >= 2000) return 'Emerald';
    if (points >= 1000) return 'Gold';
    if (points >= 500) return 'Silver';
    if (points >= 100) return 'Bronze';
    return 'Novice';
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: (json['name'] ?? json['displayName'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      profileImage: (json['profileImage'] ?? json['profile_image'] ?? json['photoURL'])?.toString(),
      points: json['points'] != null
          ? int.tryParse(json['points'].toString()) ?? 0
          : 0,
      isApproved: json['isApproved'] ?? json['is_approved'] ?? true,
      enrolledCourseIds: json['enrolledCourseIds'] != null
          ? List<String>.from(json['enrolledCourseIds'])
          : (json['enrolled_course_ids'] != null
              ? List<String>.from(json['enrolled_course_ids'])
              : null),
      teachingCourseIds: json['teachingCourseIds'] != null
          ? List<String>.from(json['teachingCourseIds'])
          : (json['teaching_course_ids'] != null
              ? List<String>.from(json['teaching_course_ids'])
              : null),
      phoneNumber: (json['phoneNumber'] ?? json['phone_number'])?.toString(),
      isBanned: json['isBanned'] ?? json['is_banned'] ?? false,
      notificationsEnabled: json['notificationsEnabled'] ?? json['notifications_enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'profileImage': profileImage,
      'profile_image': profileImage,
      'points': points,
      'isApproved': isApproved,
      'is_approved': isApproved,
      'enrolledCourseIds': enrolledCourseIds,
      'enrolled_course_ids': enrolledCourseIds,
      'teachingCourseIds': teachingCourseIds,
      'teaching_course_ids': teachingCourseIds,
      'phoneNumber': phoneNumber,
      'phone_number': phoneNumber,
      'isBanned': isBanned,
      'is_banned': isBanned,
      'notificationsEnabled': notificationsEnabled,
      'notifications_enabled': notificationsEnabled,
    };
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'profile_image': profileImage,
      'points': points,
      'is_approved': isApproved,
      'enrolled_course_ids': enrolledCourseIds ?? [],
      'teaching_course_ids': teachingCourseIds ?? [],
      'phone_number': phoneNumber,
      'is_banned': isBanned,
      'notifications_enabled': notificationsEnabled ?? true,
    };
  }
}

class Task {
  final String id;
  final String title;
  final String description;
  final String
  status; // 'pending', 'approved', 'completed', 'rejected', 'resubmitted'
  // Support multiple assignees (list of user IDs) for multi-assign
  final List<String> assignees;
  // Optional human-readable names for assignees (if included from server)
  final List<String>? assigneeNames;
  final DateTime dueDate;
  final String? creator;
  final String? rejectionReason; // Reason for rejection
  final DateTime? completedAt; // optional completion timestamp
  // Per-task bookmarks tracked as list of userIds who bookmarked
  final List<String>? bookmarkedBy;
  final List<String>?
  requestedAssigneeNames; // suggested assignee names when users request a task

  // New fields for Course/Grading support
  final String? courseId;
  final String? type; // 'homework', 'quiz', 'project', etc.
  final double? weight; // e.g., 1.0, 0.5
  final Map<String, Grade>? grades; // Map<UserId, Grade>
  final List<String>? attachments; // List of file URLs
  final Map<String, DateTime>? completionStatus; // Map<UserId, CompletedAt>
  final Map<String, List<String>>? submissions; // Map<UserId, List<FileUrl>>

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.assignees,
    this.assigneeNames,
    required this.dueDate,
    this.creator,
    this.rejectionReason,
    this.completedAt,
    this.bookmarkedBy,
    this.requestedAssigneeNames,
    this.courseId,
    this.type,
    this.weight,
    this.grades,
    this.attachments,
    this.completionStatus,
    this.submissions,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    // Parse assignees as list of strings if present, otherwise fall back to single 'assignee' field
    List<String> assignees = [];
    final rawAssignees = json['assignees'] ?? json['assignee'];
    if (rawAssignees is List) {
      assignees = List<String>.from(rawAssignees.map((e) => e.toString()));
    } else if (rawAssignees != null) {
      assignees = [rawAssignees.toString()];
    }

    List<String>? assigneeNames;
    final rawNames = json['assigneeNames'] ?? json['assignee_names'] ?? json['assigneeName'];
    if (rawNames is List) {
      assigneeNames = List<String>.from(rawNames.map((e) => e.toString()));
    } else if (rawNames != null) {
      assigneeNames = [rawNames.toString()];
    }

    List<String>? bookmarked;
    final rawBookmarked = json['bookmarkedBy'] ?? json['bookmarked_by'];
    if (rawBookmarked is List) {
      bookmarked = List<String>.from(rawBookmarked.map((e) => e.toString()));
    }

    Map<String, Grade>? gradesMap;
    if (json['grades'] != null && json['grades'] is Map) {
      gradesMap = {};
      (json['grades'] as Map<String, dynamic>).forEach((key, value) {
        if (value is Map<String, dynamic>) {
          gradesMap![key] = Grade.fromJson(value);
        }
      });
    }

    Map<String, DateTime>? completionStatusMap;
    final rawCompletion = json['completionStatus'] ?? json['completion_status'];
    if (rawCompletion != null && rawCompletion is Map) {
      completionStatusMap = {};
      (rawCompletion as Map<String, dynamic>).forEach((key, value) {
        if (value != null) {
          try {
            completionStatusMap![key] = DateTime.parse(value.toString());
          } catch (_) {}
        }
      });
    }

    Map<String, List<String>>? submissionsMap;
    if (json['submissions'] != null && json['submissions'] is Map) {
      submissionsMap = {};
      (json['submissions'] as Map<String, dynamic>).forEach((key, value) {
        if (value is List) {
          submissionsMap![key] = List<String>.from(
            value.map((e) => e.toString()),
          );
        }
      });
    }

    DateTime parsedDueDate = DateTime.now().add(const Duration(days: 7));
    final rawDueDate = json['dueDate'] ?? json['due_date'];
    if (rawDueDate != null) {
      try {
        parsedDueDate = DateTime.parse(rawDueDate.toString());
      } catch (_) {}
    }

    final rawCompletedAt = json['completedAt'] ?? json['completed_at'];
    DateTime? parsedCompletedAt;
    if (rawCompletedAt != null) {
      parsedCompletedAt = DateTime.tryParse(rawCompletedAt.toString());
    }

    final rawReqAssignees = json['requestedAssigneeNames'] ?? json['requested_assignee_names'];
    List<String>? reqAssignees;
    if (rawReqAssignees is List) {
      reqAssignees = List<String>.from(rawReqAssignees.map((e) => e.toString()));
    }

    return Task(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      assignees: assignees,
      assigneeNames: assigneeNames,
      dueDate: parsedDueDate,
      creator: json['creator']?.toString(),
      rejectionReason: (json['rejectionReason'] ?? json['rejection_reason'])?.toString(),
      completedAt: parsedCompletedAt,
      bookmarkedBy: bookmarked,
      requestedAssigneeNames: reqAssignees,
      courseId: (json['courseId'] ?? json['course_id'])?.toString(),
      type: json['type']?.toString(),
      weight: json['weight'] != null
          ? (json['weight'] as num).toDouble()
          : null,
      grades: gradesMap,
      attachments: json['attachments'] != null
          ? List<String>.from(json['attachments'])
          : null,
      completionStatus: completionStatusMap,
      submissions: submissionsMap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'assignees': assignees,
      'assigneeNames': assigneeNames,
      'assignee_names': assigneeNames,
      'dueDate': dueDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'creator': creator,
      'rejectionReason': rejectionReason,
      'rejection_reason': rejectionReason,
      'completedAt': completedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'bookmarkedBy': bookmarkedBy,
      'bookmarked_by': bookmarkedBy,
      'requestedAssigneeNames': requestedAssigneeNames,
      'requested_assignee_names': requestedAssigneeNames,
      'courseId': courseId,
      'course_id': courseId,
      'type': type,
      'weight': weight,
      'grades': grades?.map((k, v) => MapEntry(k, v.toJson())),
      'attachments': attachments,
      'completionStatus': completionStatus?.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ),
      'completion_status': completionStatus?.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ),
      'submissions': submissions,
    };
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'assignees': assignees,
      'assignee_names': assigneeNames ?? [],
      'due_date': dueDate.toIso8601String(),
      'creator': creator,
      'rejection_reason': rejectionReason,
      'completed_at': completedAt?.toIso8601String(),
      'bookmarked_by': bookmarkedBy ?? [],
      'requested_assignee_names': requestedAssigneeNames ?? [],
      'course_id': courseId,
      'type': type,
      'weight': weight,
      'grades': grades?.map((k, v) => MapEntry(k, v.toJson())) ?? {},
      'attachments': attachments ?? [],
      'completion_status': completionStatus?.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ) ?? {},
      'submissions': submissions ?? {},
    };
  }
}
