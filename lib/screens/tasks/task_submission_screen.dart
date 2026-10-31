import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../services/firestore_task_service.dart';
import '../../services/storage_service.dart';

class TaskSubmissionScreen extends StatefulWidget {
  final Task task;
  final User user;

  const TaskSubmissionScreen({
    super.key,
    required this.task,
    required this.user,
  });

  @override
  State<TaskSubmissionScreen> createState() => _TaskSubmissionScreenState();
}

class _TaskSubmissionScreenState extends State<TaskSubmissionScreen> {
  final List<PlatformFile> _newPickedFiles = [];
  late List<String> _existingUrls;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load previously submitted files for this user, or task attachments
    final previousSubmissions =
        widget.task.submissions?[widget.user.id] ?? widget.task.attachments;
    _existingUrls = previousSubmissions != null
        ? List<String>.from(previousSubmissions)
        : [];
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'zip', 'doc', 'docx'],
      );

      if (result != null) {
        setState(() {
          _newPickedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking files: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitOrUpdateTask() async {
    final totalFilesCount = _existingUrls.length + _newPickedFiles.length;

    if (totalFilesCount == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Files Attached'),
          content: const Text(
            'Are you sure you want to submit your output without any attachments?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit Anyway'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      if (!mounted) return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    final storageService = StorageService();
    final taskService = Provider.of<FirestoreTaskService>(
      context,
      listen: false,
    );
    final newlyUploadedUrls = <String>[];

    try {
      // Upload new files to Cloudinary
      for (int i = 0; i < _newPickedFiles.length; i++) {
        final file = _newPickedFiles[i];
        if (file.path == null) continue;

        final url = await storageService.uploadFile(
          File(file.path!),
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _uploadProgress =
                  _newPickedFiles.isEmpty
                      ? 1.0
                      : (i + progress) / _newPickedFiles.length;
            });
          },
        );

        if (url != null && url.isNotEmpty) {
          newlyUploadedUrls.add(url);
        }
      }

      // Combine existing URLs that were kept + new URLs
      final combinedUrls = [..._existingUrls, ...newlyUploadedUrls];

      // Submit to Supabase
      await taskService.submitTask(
        widget.task.id,
        widget.user.id,
        combinedUrls,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _existingUrls.isNotEmpty
                ? 'Output updated successfully! 🎉'
                : 'Task submitted successfully! 🚀',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final status = widget.task.status.toLowerCase();
    final isApproved = status == 'approved' || status == 'completed';
    final isRejected = status == 'rejected';
    final isUnderReview = status == 'pending' || status == 'resubmitted';

    final hasExistingFiles = _existingUrls.isNotEmpty;
    final isUpdating = hasExistingFiles || isUnderReview || isRejected;

    return Scaffold(
      appBar: AppBar(
        title: Text(isUpdating ? 'Update Output' : 'Submit Task Output'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Task Information Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              color: Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            widget.task.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        _buildStatusBadge(status),
                      ],
                    ),
                    if (widget.task.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.task.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Due: ${DateFormat('MMM dd, yyyy').format(widget.task.dueDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status Notice Banner
            if (isRejected && widget.task.rejectionReason != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Revision Requested by Professor:',
                            style: TextStyle(
                              color: Color(0xFF991B1B),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.task.rejectionReason!,
                            style: const TextStyle(
                              color: Color(0xFF7F1D1D),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Please modify your output files below and resubmit.',
                            style: TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (isUnderReview)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.hourglass_top,
                      color: Colors.amber,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Output Under Review',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Your output was submitted. You can still update or replace your attachments before the professor finalizes evaluation.',
                            style: TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (isApproved)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Task Completed & Approved! Your output is stored safely.',
                        style: TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Existing Submitted Files Section
            if (_existingUrls.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current Submitted Files (${_existingUrls.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (!isApproved)
                    Text(
                      'Tap ❌ to remove',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _existingUrls.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final url = _existingUrls[index];
                  final isImg = _isImageUrl(url);
                  final fileName = _getFileName(url);

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: isImg
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                url,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image,
                                  color: Colors.blue,
                                ),
                              ),
                            )
                          : Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.insert_drive_file,
                                color: Colors.blue,
                              ),
                            ),
                      title: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: const Text(
                        'Stored on Cloudinary',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isImg)
                            IconButton(
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 20,
                                color: Colors.blue,
                              ),
                              tooltip: 'Preview Image',
                              onPressed: () => _previewImage(context, url),
                            ),
                          if (!isApproved)
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 20,
                                color: Colors.red,
                              ),
                              tooltip: 'Remove',
                              onPressed: () {
                                setState(() {
                                  _existingUrls.removeAt(index);
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],

            // Add New Files Section
            if (!isApproved) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Attach New Files',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isUploading ? null : _pickFiles,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Browse Files'),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Upload Drop Area
              InkWell(
                onTap: _isUploading ? null : _pickFiles,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 38,
                          color: Colors.blue.shade400,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap to select files from device',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PDF, JPG, PNG, DOCX, ZIP supported',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Newly Picked Files List
              if (_newPickedFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _newPickedFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final file = _newPickedFiles[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.upload_file,
                            color: Colors.green,
                          ),
                        ),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${(file.size / 1024).toStringAsFixed(1)} KB — Ready to upload',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _newPickedFiles.removeAt(index);
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
            ],

            // Upload Progress Bar
            if (_isUploading) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: Colors.blue.shade100,
                      color: const Color(0xFF2563EB),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Uploading files to Cloudinary... ${(_uploadProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E40AF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (!isApproved) ...[
              // Action Button
              ElevatedButton.icon(
                onPressed: _submitOrUpdateTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: Icon(
                  _existingUrls.isNotEmpty
                      ? Icons.sync
                      : Icons.arrow_upward_rounded,
                ),
                label: Text(
                  _existingUrls.isNotEmpty
                      ? 'Update Output & Resubmit'
                      : 'Submit Output',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],

            if (isApproved) ...[
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Tasks'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;
    String label = status.toUpperCase();

    switch (status) {
      case 'completed':
      case 'approved':
        bg = const Color(0xFFDCFCE7);
        text = const Color(0xFF15803D);
        label = 'COMPLETED';
        break;
      case 'pending':
        bg = const Color(0xFFFEF3C7);
        text = const Color(0xFFB45309);
        label = 'UNDER REVIEW';
        break;
      case 'resubmitted':
        bg = const Color(0xFFF3E8FF);
        text = const Color(0xFF7E22CE);
        label = 'RESUBMITTED';
        break;
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        text = const Color(0xFFB91C1C);
        label = 'NEEDS REVISION';
        break;
      default:
        bg = Colors.grey.shade200;
        text = Colors.grey.shade700;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
