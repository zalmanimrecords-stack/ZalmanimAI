import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/api_client.dart';
import '../../core/loading_error_widgets.dart';

/// Public form for artist to submit full details after their track was approved.
/// Route: /pending-release?token=xxx (no login).
class PendingReleaseFormPage extends StatefulWidget {
  const PendingReleaseFormPage({
    super.key,
    required this.apiClient,
    required this.token,
  });

  final ApiClient apiClient;
  final String token;

  @override
  State<PendingReleaseFormPage> createState() => _PendingReleaseFormPageState();
}

class _PendingReleaseFormPageState extends State<PendingReleaseFormPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _artistName;
  String? _releaseTitle;
  DateTime? _expiresAt;
  bool _uploadingReferenceImage = false;
  bool _masteringRequired = false;
  bool _masteringHeadroomConfirmed = false;
  String? _referenceImageUrl;
  String? _referenceImageName;

  final _artistNameController = TextEditingController();
  final _artistEmailController = TextEditingController();
  final _artistBrandController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _websiteController = TextEditingController();
  final _soundcloudController = TextEditingController();
  final _instagramController = TextEditingController();
  final _facebookController = TextEditingController();
  final _releaseTitleController = TextEditingController();
  final _trackTitleController = TextEditingController();
  final _catalogNumberController = TextEditingController();
  final _releaseDateController = TextEditingController();
  final _wavDownloadUrlController = TextEditingController();
  final _musicalStyleController = TextEditingController();
  final _marketingTextController = TextEditingController();
  final _releaseStoryController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _artistNameController.dispose();
    _artistEmailController.dispose();
    _artistBrandController.dispose();
    _fullNameController.dispose();
    _websiteController.dispose();
    _soundcloudController.dispose();
    _instagramController.dispose();
    _facebookController.dispose();
    _releaseTitleController.dispose();
    _trackTitleController.dispose();
    _catalogNumberController.dispose();
    _releaseDateController.dispose();
    _wavDownloadUrlController.dispose();
    _musicalStyleController.dispose();
    _marketingTextController.dispose();
    _releaseStoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.apiClient.fetchPendingReleaseFormInfo(widget.token);
      final artistData = data['artist_data'] is Map<String, dynamic>
          ? data['artist_data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final releaseData = data['release_data'] is Map<String, dynamic>
          ? data['release_data'] as Map<String, dynamic>
          : <String, dynamic>{};
      setState(() {
        _artistName = data['artist_name']?.toString();
        _releaseTitle = data['release_title']?.toString();
        _expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '');
        _artistNameController.text = _artistName ?? '';
        _artistEmailController.text = data['artist_email']?.toString() ?? '';
        _artistBrandController.text = artistData['artist_brand']?.toString() ?? '';
        _fullNameController.text = artistData['full_name']?.toString() ?? '';
        _websiteController.text = artistData['website']?.toString() ?? '';
        _soundcloudController.text = artistData['soundcloud']?.toString() ?? '';
        _instagramController.text = artistData['instagram']?.toString() ?? '';
        _facebookController.text = artistData['facebook']?.toString() ?? '';
        _releaseTitleController.text = _releaseTitle ?? '';
        _trackTitleController.text = releaseData['track_title']?.toString() ?? '';
        _catalogNumberController.text =
            releaseData['release_number']?.toString() ?? releaseData['catalog_number']?.toString() ?? '';
        _releaseDateController.text = releaseData['release_date']?.toString() ?? '';
        _wavDownloadUrlController.text = releaseData['wav_download_url']?.toString() ?? '';
        _musicalStyleController.text =
            releaseData['musical_style']?.toString() ?? releaseData['genre']?.toString() ?? '';
        _marketingTextController.text = releaseData['marketing_text']?.toString() ?? '';
        _releaseStoryController.text = releaseData['release_story']?.toString() ?? '';
        _notesController.text = releaseData['notes']?.toString() ?? '';
        _masteringRequired = releaseData['mastering_required'] == true;
        _masteringHeadroomConfirmed = releaseData['mastering_headroom_confirmed'] == true;
        _referenceImageUrl = releaseData['cover_reference_image_url']?.toString();
        _referenceImageName = releaseData['cover_reference_image_name']?.toString();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final name = _artistNameController.text.trim();
    final email = _artistEmailController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter artist name.');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = 'Please enter email.');
      return;
    }
    final releaseTitle = _releaseTitleController.text.trim();
    if (releaseTitle.isEmpty) {
      setState(() => _error = 'Please enter release title.');
      return;
    }
    if (_masteringRequired && !_masteringHeadroomConfirmed) {
      setState(() => _error = 'Please confirm the files will be delivered with 6 dB headroom for mastering.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final artistData = <String, dynamic>{
        if (_artistBrandController.text.trim().isNotEmpty) 'artist_brand': _artistBrandController.text.trim(),
        if (_fullNameController.text.trim().isNotEmpty) 'full_name': _fullNameController.text.trim(),
        if (_websiteController.text.trim().isNotEmpty) 'website': _websiteController.text.trim(),
        if (_soundcloudController.text.trim().isNotEmpty) 'soundcloud': _soundcloudController.text.trim(),
        if (_instagramController.text.trim().isNotEmpty) 'instagram': _instagramController.text.trim(),
        if (_facebookController.text.trim().isNotEmpty) 'facebook': _facebookController.text.trim(),
      };
      final releaseData = <String, dynamic>{
        if (_trackTitleController.text.trim().isNotEmpty) 'track_title': _trackTitleController.text.trim(),
        if (_catalogNumberController.text.trim().isNotEmpty) ...{
          'catalog_number': _catalogNumberController.text.trim(),
          'release_number': _catalogNumberController.text.trim(),
        },
        if (_releaseDateController.text.trim().isNotEmpty) 'release_date': _releaseDateController.text.trim(),
        if (_wavDownloadUrlController.text.trim().isNotEmpty) 'wav_download_url': _wavDownloadUrlController.text.trim(),
        if (_musicalStyleController.text.trim().isNotEmpty) ...{
          'musical_style': _musicalStyleController.text.trim(),
          'genre': _musicalStyleController.text.trim(),
        },
        'mastering_required': _masteringRequired,
        'mastering_headroom_confirmed': _masteringHeadroomConfirmed,
        if ((_referenceImageUrl ?? '').trim().isNotEmpty) 'cover_reference_image_url': _referenceImageUrl!.trim(),
        if ((_referenceImageName ?? '').trim().isNotEmpty) 'cover_reference_image_name': _referenceImageName!.trim(),
        if (_marketingTextController.text.trim().isNotEmpty) 'marketing_text': _marketingTextController.text.trim(),
        if (_releaseStoryController.text.trim().isNotEmpty) 'release_story': _releaseStoryController.text.trim(),
        if (_notesController.text.trim().isNotEmpty) 'notes': _notesController.text.trim(),
      };
      await widget.apiClient.submitPendingRelease(
        token: widget.token,
        artistName: name,
        artistEmail: email,
        artistData: artistData,
        releaseTitle: releaseTitle,
        releaseData: releaseData,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Thank you'),
          content: const Text(
            'Your details have been submitted. The label will process your release and get in touch.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _pickAndUploadReferenceImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = (result == null || result.files.isEmpty) ? null : result.files.first;
    if (file == null || file.bytes == null || file.bytes!.isEmpty) return;
    setState(() {
      _uploadingReferenceImage = true;
      _error = null;
    });
    try {
      final data = await widget.apiClient.uploadPendingReleaseReferenceImage(
        token: widget.token,
        fileBytes: file.bytes!,
        filename: file.name.isEmpty ? 'reference-image.png' : file.name,
      );
      if (!mounted) return;
      setState(() {
        _referenceImageUrl = data['url']?.toString();
        _referenceImageName = data['filename']?.toString() ?? file.name;
        _uploadingReferenceImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingReferenceImage = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return Scaffold(
        body: LoadingView(primary: primary),
      );
    }

    if (_error != null && _artistName == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pending release')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SelectableText(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: _error!)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Release details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Please fill in your full artist details and track/release information so we can proceed with your release.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
          ),
          if (_expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'This link is available until ${_expiresAt!.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Artist details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: _artistNameController,
            decoration: const InputDecoration(
              labelText: 'Artist name *',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _artistEmailController,
            decoration: const InputDecoration(
              labelText: 'Email *',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _artistBrandController,
            decoration: const InputDecoration(
              labelText: 'Artist brand',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _fullNameController,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _websiteController,
            decoration: const InputDecoration(
              labelText: 'Website',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _soundcloudController,
            decoration: const InputDecoration(
              labelText: 'SoundCloud',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _instagramController,
            decoration: const InputDecoration(
              labelText: 'Instagram',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _facebookController,
            decoration: const InputDecoration(
              labelText: 'Facebook',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 24),
          const Text('Release / track details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: _releaseTitleController,
            decoration: const InputDecoration(
              labelText: 'Release title *',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _trackTitleController,
            decoration: const InputDecoration(
              labelText: 'Track title',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _catalogNumberController,
            decoration: const InputDecoration(
              labelText: 'Release number / catalog number',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _releaseDateController,
            decoration: const InputDecoration(
              labelText: 'Release date (e.g. 2025-04-01)',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _wavDownloadUrlController,
            decoration: const InputDecoration(
              labelText: 'WAV download link',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mastering is needed for this release'),
            subtitle: const Text('If enabled, please deliver the files with 6 dB headroom.'),
            value: _masteringRequired,
            onChanged: (value) => setState(() {
              _masteringRequired = value;
              if (!value) _masteringHeadroomConfirmed = false;
            }),
          ),
          if (_masteringRequired)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I confirm the files will be delivered at -6 dB headroom'),
              value: _masteringHeadroomConfirmed,
              onChanged: (value) => setState(() => _masteringHeadroomConfirmed = value ?? false),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _musicalStyleController,
            decoration: const InputDecoration(
              labelText: 'Musical style',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _uploadingReferenceImage ? null : _pickAndUploadReferenceImage,
                  icon: _uploadingReferenceImage
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_outlined),
                  label: Text(_uploadingReferenceImage ? 'Uploading image...' : 'Upload cover reference image'),
                ),
                if ((_referenceImageName ?? '').isNotEmpty)
                  Text(
                    _referenceImageName!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if ((_referenceImageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _referenceImageUrl!,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: Colors.grey.shade200,
                  child: const Text('Could not preview image'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _marketingTextController,
            decoration: const InputDecoration(
              labelText: 'Marketing text about the release',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _releaseStoryController,
            decoration: const InputDecoration(
              labelText: 'What is the release about?',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textInputAction: TextInputAction.done,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SelectableText(_error!, style: const TextStyle(color: Colors.red)),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: _error!)),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
