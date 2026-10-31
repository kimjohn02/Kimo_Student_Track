// lib/screens/tasks/admin_tasks_approval_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../services/task_service.dart';
import '../../services/firestore_task_service.dart';

class AdminTasksApprovalScreen extends StatefulWidget {
  final User user;

  const AdminTasksApprovalScreen({super.key, required this.user});

  @override
  State<AdminTasksApprovalScreen> createState() =>
      _AdminTasksApprovalScreenState();
}

class _AdminTasksApprovalScreenState extends State<AdminTasksApprovalScreen> {
  String _filterStatus = 'all'; // 'all', 'pending', 'approvals', 'completed'
  String _searchQuery = '';

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showRejectDialog(
    BuildContext context,
    String taskId,
    FirestoreTaskService firestoreTaskService,
  ) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.assignment_return, color: Colors.red),
            SizedBox(width: 8),
            Text('Request Revision / Reject'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Provide feedback so the student knows what to revise in their output:',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: 'e.g. Please format Chapter 3 and re-upload the PDF.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                _showFeedback(context, 'Please enter a rejection reason');
                return;
              }
              await firestoreTaskService.rejectTask(taskId, reason);
              if (!context.mounted) return;
              Navigator.pop(context);
              _showFeedback(context, 'Task returned to student for revision.');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Send Revision Request',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showApprovePointsDialog(
    BuildContext context,
    Task task,
    FirestoreTaskService firestoreTaskService,
    String? studentId,
  ) {
    int rewardPoints = 10;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text('Approve & Award Points'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Approving output for: "${task.title}"',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reward Points for Student:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 10, 20, 50].map((pts) {
                  final isSelected = rewardPoints == pts;
                  return ChoiceChip(
                    label: Text('+$pts pts'),
                    selected: isSelected,
                    selectedColor: Colors.green.shade100,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.green.shade900 : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) {
                      setDialogState(() => rewardPoints = pts);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (studentId != null && studentId.isNotEmpty) {
                  await firestoreTaskService.markTaskComplete(
                    task.id,
                    completedBy: studentId,
                    rewardPoints: rewardPoints,
                  );
                } else {
                  await firestoreTaskService.approveTask(task.id);
                }
                if (!context.mounted) return;
                _showFeedback(
                  context,
                  'Task Approved and +$rewardPoints points awarded! 🌟',
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text(
                'Approve Output',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('.gif');
  }

  String _getFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final segment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url;
      return Uri.decodeComponent(segment);
    } catch (_) {
      return url.split('/').last;
    }
  }

  void _previewImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      'Unable to load preview',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showFileDetailsDialog(
    BuildContext context,
    String fileName,
    String fileUrl,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.insert_drive_file, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attached file URL (Cloudinary):',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                fileUrl,
                style: const TextStyle(fontSize: 11, color: Colors.blue),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fileUrl));
              Navigator.pop(ctx);
              _showFeedback(context, 'File URL copied to clipboard! 📋');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskService = Provider.of<TaskService>(context);
    final firestoreTaskService = Provider.of<FirestoreTaskService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Review & Approve Outputs',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by task title or student...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildFilterChip('All', isSelected: _filterStatus == 'all', onTap: () {
                  setState(() => _filterStatus = 'all');
                }),
                const SizedBox(width: 8),
                _buildFilterChip('Pending Review', isSelected: _filterStatus == 'pending', onTap: () {
                  setState(() => _filterStatus = 'pending');
                }),
                const SizedBox(width: 8),
                _buildFilterChip('Needs Approval', isSelected: _filterStatus == 'approvals', onTap: () {
                  setState(() => _filterStatus = 'approvals');
                }),
                const SizedBox(width: 8),
                _buildFilterChip('Completed', isSelected: _filterStatus == 'completed', onTap: () {
                  setState(() => _filterStatus = 'completed');
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Task List (Real-time from Supabase)
          Expanded(
            child: StreamBuilder<List<Task>>(
              stream: firestoreTaskService.tasksStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allTasks = snapshot.data ?? [];

                // Apply filter
                List<Task> filteredTasks = allTasks.where((t) {
                  final statusLc = t.status.toLowerCase();
                  if (_filterStatus == 'pending') {
                    if (statusLc != 'pending' && statusLc != 'resubmitted') return false;
                  } else if (_filterStatus == 'approvals') {
                    if (statusLc != 'pending_approval') return false;
                  } else if (_filterStatus == 'completed') {
                    if (statusLc != 'completed' && statusLc != 'approved') return false;
                  }

                  if (_searchQuery.isNotEmpty) {
                    final titleMatch = t.title.toLowerCase().contains(_searchQuery);
                    final assigneeId = t.assignees.isNotEmpty ? t.assignees.first : '';
                    final nameMatch = taskService.getUserName(assigneeId).toLowerCase().contains(_searchQuery);
                    if (!titleMatch && !nameMatch) return false;
                  }
                  return true;
                }).toList();

                if (filteredTasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_turned_in_outlined,
                          size: 56,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _filterStatus == 'pending'
                              ? 'No pending student outputs to review.'
                              : 'No tasks found.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filteredTasks.length,
                  itemBuilder: (context, index) {
                    final task = filteredTasks[index];
                    final assigneeId = task.assignees.isNotEmpty
                        ? task.assignees.first
                        : '';
                    final assigneeName = assigneeId.isNotEmpty
                        ? taskService.getUserName(assigneeId)
                        : '';
                    return _buildTaskReviewCard(
                      context,
                      task,
                      firestoreTaskService,
                      assigneeName,
                      assigneeId,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, {required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: Colors.blue.withAlpha((0.15 * 255).round()),
        labelStyle: TextStyle(
          color: isSelected ? Colors.blue.shade800 : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        onSelected: (_) => onTap(),
        backgroundColor: Colors.grey.shade200,
      ),
    );
  }

  Widget _buildTaskReviewCard(
    BuildContext context,
    Task task,
    FirestoreTaskService firestoreTaskService,
    String assigneeName,
    String assigneeId,
  ) {
    final statusLc = task.status.toLowerCase();
    final isPendingSubmission =
        statusLc == 'pending' || statusLc == 'resubmitted';
    final isPendingApproval = statusLc == 'pending_approval';
    final isRejected = statusLc == 'rejected';
    final isCompleted = statusLc == 'approved' || statusLc == 'completed';

    final Color statusColor = (isPendingSubmission || isPendingApproval)
        ? Colors.amber.shade800
        : (isCompleted ? Colors.green.shade700 : Colors.red.shade700);

    String statusText = task.status.toUpperCase();
    if (isPendingApproval) statusText = 'CREATOR APPROVAL';
    if (isPendingSubmission) statusText = 'PENDING REVIEW';

    // Collect all submitted output files for this task
    final List<String> outputFiles = [];
    if (task.submissions != null && task.submissions!.isNotEmpty) {
      if (assigneeId.isNotEmpty && task.submissions!.containsKey(assigneeId)) {
        outputFiles.addAll(task.submissions![assigneeId] ?? []);
      } else {
        task.submissions!.forEach((_, files) => outputFiles.addAll(files));
      }
    } else if (task.attachments != null) {
      outputFiles.addAll(task.attachments!);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title & Status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            assigneeName.isNotEmpty
                                ? 'Student: $assigneeName'
                                : (task.creator != null ? 'Created by ${task.creator}' : 'Unassigned'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha((0.12 * 255).round()),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Student Submitted Output Section (ilaha output) ─────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Submitted Output Files:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
                Text(
                  '${outputFiles.length} file(s)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (outputFiles.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: outputFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final url = outputFiles[i];
                    final isImg = _isImageUrl(url);
                    final fileName = _getFileName(url);

                    return InkWell(
                      onTap: () {
                        if (isImg) {
                          _previewImage(context, url);
                        } else {
                          _showFileDetailsDialog(context, fileName, url);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 150,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50.withAlpha(80),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Row(
                          children: [
                            if (isImg)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  url,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image,
                                    size: 24,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.insert_drive_file,
                                  color: Colors.blue,
                                  size: 22,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Tap to preview',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'No files submitted yet by the student.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),

            // Rejection reason if previously rejected
            if (isRejected && task.rejectionReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Previous Revision Note: ${task.rejectionReason}',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Action Buttons for Professor / Admin
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isPendingSubmission || isPendingApproval) ...[
                  // Reject / Request Revision Button
                  OutlinedButton.icon(
                    onPressed: () {
                      _showRejectDialog(context, task.id, firestoreTaskService);
                    },
                    icon: const Icon(Icons.close, size: 14, color: Colors.red),
                    label: const Text(
                      'Request Revision',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Approve Output Button
                  ElevatedButton.icon(
                    onPressed: () {
                      if (isPendingApproval) {
                        firestoreTaskService.approveProfessorTask(task.id);
                        _showFeedback(context, 'Task Approved (Assigned).');
                      } else {
                        _showApprovePointsDialog(
                          context,
                          task,
                          firestoreTaskService,
                          assigneeId,
                        );
                      }
                    },
                    icon: const Icon(Icons.check, size: 14, color: Colors.white),
                    label: const Text(
                      'Approve Output',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ] else if (isRejected) ...[
                  // Resubmit option
                  ElevatedButton.icon(
                    onPressed: () async {
                      await firestoreTaskService.resubmitTask(task.id);
                      if (!context.mounted) return;
                      _showFeedback(context, 'Task marked for resubmission.');
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Allow Resubmit', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ] else if (isCompleted) ...[
                  Row(
                    children: [
                      const Icon(Icons.verified, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Evaluated & Completed',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
