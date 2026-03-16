import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';

/// Public form for artist to confirm and complete details after their demo was approved.
/// Route: /demo-confirm?token=xxx (no login).
/// Prefilled from demo submission; on submit the track moves to PENDING RELEASE.
class DemoConfirmFormPage extends StatefulWidget {
  const DemoConfirmFormPage({
    super.key,
    required this.apiClient,
    required this.token,
  });

  final ApiClient apiClient;
  final String token;

  @override
  State<DemoConfirmFormPage> createState() => _DemoConfirmFormPageState();
}

class _DemoConfirmFormPageState extends State<DemoConfirmFormPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  final _artistNameController = TextEditingController();
  final _artistEmailController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _genreController = TextEditingController();
  final _cityController = TextEditingController();
  final _messageController = TextEditingController();
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
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _artistNameController.dispose();
    _artistEmailController.dispose();
    _contactNameController.dispose();
    _phoneController.dispose();
    _genreController.dispose();
    _cityController.dispose();
    _messageController.dispose();
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
      final data = await widget.apiClient.fetchDemoConfirmFormInfo(widget.token);
      setState(() {
        _artistNameController.text = (data['artist_name'] ?? '').toString();
        _artistEmailController.text = (data['email'] ?? '').toString();
        _contactNameController.text = (data['contact_name'] ?? '').toString();
        _phoneController.text = (data['phone'] ?? '').toString();
        _genreController.text = (data['genre'] ?? '').toString();
        _cityController.text = (data['city'] ?? '').toString();
        _messageController.text = (data['message'] ?? '').toString();
        _releaseTitleController.text = (data['release_title'] ?? 'Your release').toString();
        final links = data['links'];
        if (links is List && links.isNotEmpty) {
          _notesController.text = links.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).join('\n');
        }
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
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final artistData = <String, dynamic>{
        if (_contactNameController.text.trim().isNotEmpty) 'full_name': _contactNameController.text.trim(),
        if (_artistBrandController.text.trim().isNotEmpty) 'artist_brand': _artistBrandController.text.trim(),
        if (_phoneController.text.trim().isNotEmpty) 'phone': _phoneController.text.trim(),
        if (_genreController.text.trim().isNotEmpty) 'genre': _genreController.text.trim(),
        if (_cityController.text.trim().isNotEmpty) 'city': _cityController.text.trim(),
        if (_websiteController.text.trim().isNotEmpty) 'website': _websiteController.text.trim(),
        if (_soundcloudController.text.trim().isNotEmpty) 'soundcloud': _soundcloudController.text.trim(),
        if (_instagramController.text.trim().isNotEmpty) 'instagram': _instagramController.text.trim(),
        if (_facebookController.text.trim().isNotEmpty) 'facebook': _facebookController.text.trim(),
        if (_messageController.text.trim().isNotEmpty) 'message': _messageController.text.trim(),
      };
      final releaseData = <String, dynamic>{
        if (_trackTitleController.text.trim().isNotEmpty) 'track_title': _trackTitleController.text.trim(),
        if (_catalogNumberController.text.trim().isNotEmpty) 'catalog_number': _catalogNumberController.text.trim(),
        if (_releaseDateController.text.trim().isNotEmpty) 'release_date': _releaseDateController.text.trim(),
        if (_notesController.text.trim().isNotEmpty) 'notes': _notesController.text.trim(),
      };
      await widget.apiClient.submitDemoConfirm(
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
            'Your details have been submitted. Your track is now in PENDING RELEASE. '
            'The label will process it and get in touch.',
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

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primary),
              const SizedBox(height: 16),
              Text(AppConfig.labelName, style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    if (_error != null && _artistNameController.text.isEmpty && _artistEmailController.text.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm your details')),
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
        title: const Text('Confirm your details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Please confirm your details below and complete any missing fields. '
            'Once you submit, your track will move to PENDING RELEASE until the label releases it.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
          ),
          const SizedBox(height: 24),
          const Text('Your details (from demo)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
            controller: _contactNameController,
            decoration: const InputDecoration(
              labelText: 'Contact / full name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _genreController,
            decoration: const InputDecoration(
              labelText: 'Genre',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cityController,
            decoration: const InputDecoration(
              labelText: 'City',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: 'Message / comments',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 24),
          const Text('Additional artist info', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
              labelText: 'Catalog number',
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
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes / links',
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
                : const Text('Confirm and submit'),
          ),
        ],
      ),
    );
  }
}
