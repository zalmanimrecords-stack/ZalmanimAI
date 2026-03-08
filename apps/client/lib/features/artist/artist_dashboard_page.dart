import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../widgets/api_connection_indicator.dart';

class ArtistDashboardPage extends StatefulWidget {
  const ArtistDashboardPage({super.key, required this.apiClient, required this.token});

  final ApiClient apiClient;
  final String token;

  @override
  State<ArtistDashboardPage> createState() => _ArtistDashboardPageState();
}

class _ArtistDashboardPageState extends State<ArtistDashboardPage> {
  final titleController = TextEditingController();
  bool loading = true;
  bool uploading = false;
  String? error;
  Map<String, dynamic>? dashboard;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final releases = (dashboard?['releases'] as List<dynamic>? ?? const []);
    final tasks = (dashboard?['tasks'] as List<dynamic>? ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artist Portal'),
        actions: [ApiConnectionIndicator(apiClient: widget.apiClient, onConnectionRestored: _load)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy error',
                          onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Welcome ${(dashboard?['artist'] as Map<String, dynamic>)['name']}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Upload New Music', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: titleController,
                                decoration: const InputDecoration(labelText: 'Track title'),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: uploading ? null : _pickAndUpload,
                                child: Text(uploading ? 'Uploading...' : 'Select file and upload'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Recent Releases', style: TextStyle(fontWeight: FontWeight.bold)),
                      ...releases.map((r) {
                        final item = r as Map<String, dynamic>;
                        return ListTile(
                          leading: const Icon(Icons.music_note),
                          title: Text(item['title'] as String),
                          subtitle: Text('Status: ${item['status']}'),
                        );
                      }),
                      const SizedBox(height: 16),
                      const Text('System Tasks', style: TextStyle(fontWeight: FontWeight.bold)),
                      ...tasks.map((t) {
                        final item = t as Map<String, dynamic>;
                        return ListTile(
                          leading: const Icon(Icons.task_alt),
                          title: Text(item['title'] as String),
                          subtitle: Text('${item['status']} | ${item['details']}'),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }

  Future<void> _load() async {
    try {
      final result = await widget.apiClient.fetchArtistDashboard(widget.token);
      setState(() {
        dashboard = result;
        error = null;
        loading = false;
      });
    } catch (e) {
      final msg = e.toString();
      final isConnectionError = msg.contains('Failed to fetch') ||
          msg.contains('Connection refused') ||
          msg.contains('SocketException') ||
          msg.contains('ClientException');
      setState(() {
        error = isConnectionError
            ? 'Cannot reach API at ${widget.apiClient.baseUrl}. Backend running? Stop the app and run again (full restart). Or run: docker compose up -d'
            : msg;
        loading = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    if (titleController.text.trim().isEmpty) {
      setState(() => error = 'Please enter track title first');
      return;
    }

    // Use bytes: on web path is unavailable and accessing it throws (file_picker FAQ).
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.bytes == null || f.bytes!.isEmpty) {
      setState(() => error = 'Could not read file. Please try again.');
      return;
    }

    setState(() {
      uploading = true;
      error = null;
    });

    try {
      await widget.apiClient.uploadRelease(
        token: widget.token,
        title: titleController.text.trim(),
        fileBytes: f.bytes!,
        filename: f.name,
      );
      titleController.clear();
      await _load();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }
}
