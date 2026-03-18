import 'package:flutter/material.dart';

import '../../core/api_client.dart';

class ArtistRegistrationFormPage extends StatefulWidget {
  const ArtistRegistrationFormPage({
    super.key,
    required this.apiClient,
    required this.token,
  });

  final ApiClient apiClient;
  final String token;

  @override
  State<ArtistRegistrationFormPage> createState() =>
      _ArtistRegistrationFormPageState();
}

class _ArtistRegistrationFormPageState
    extends State<ArtistRegistrationFormPage> {
  final _artistNameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _websiteController = TextEditingController();
  final _soundcloudController = TextEditingController();
  final _instagramController = TextEditingController();
  final _spotifyController = TextEditingController();
  final _appleMusicController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _facebookController = TextEditingController();
  final _linktreeController = TextEditingController();
  final _notesController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _completed = false;
  String? _error;
  String _email = '';
  String _portalUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _artistNameController.dispose();
    _fullNameController.dispose();
    _websiteController.dispose();
    _soundcloudController.dispose();
    _instagramController.dispose();
    _spotifyController.dispose();
    _appleMusicController.dispose();
    _youtubeController.dispose();
    _tiktokController.dispose();
    _facebookController.dispose();
    _linktreeController.dispose();
    _notesController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await widget.apiClient.fetchArtistRegistrationForm(widget.token);
      if (!mounted) return;
      setState(() {
        _email = data['email']?.toString() ?? '';
        _artistNameController.text = data['artist_name']?.toString() ?? '';
        _fullNameController.text = data['full_name']?.toString() ?? '';
        _notesController.text = data['notes']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_artistNameController.text.trim().isEmpty) {
      setState(() => _error = 'Artist name is required.');
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.submitArtistRegistration(
        token: widget.token,
        artistName: _artistNameController.text.trim(),
        fullName: _fullNameController.text.trim().isEmpty
            ? null
            : _fullNameController.text.trim(),
        website: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        soundcloud: _soundcloudController.text.trim().isEmpty
            ? null
            : _soundcloudController.text.trim(),
        instagram: _instagramController.text.trim().isEmpty
            ? null
            : _instagramController.text.trim(),
        spotify: _spotifyController.text.trim().isEmpty
            ? null
            : _spotifyController.text.trim(),
        appleMusic: _appleMusicController.text.trim().isEmpty
            ? null
            : _appleMusicController.text.trim(),
        youtube: _youtubeController.text.trim().isEmpty
            ? null
            : _youtubeController.text.trim(),
        tiktok: _tiktokController.text.trim().isEmpty
            ? null
            : _tiktokController.text.trim(),
        facebook: _facebookController.text.trim().isEmpty
            ? null
            : _facebookController.text.trim(),
        linktree: _linktreeController.text.trim().isEmpty
            ? null
            : _linktreeController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _portalUrl = result['portal_url']?.toString() ?? '';
        _completed = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artist registration'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _completed
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: primary, size: 40),
                              const SizedBox(height: 16),
                              Text(
                                'Registration completed',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Your artist profile is now ready. You can sign in to the portal with the email and password you just created.',
                              ),
                              if (_portalUrl.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                SelectableText(_portalUrl),
                              ],
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Complete your registration to access the artist portal',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Fill in your details once. After submitting, you will be able to sign in to the portal and continue working with the label.',
                              ),
                              const SizedBox(height: 16),
                              _readOnlyField(label: 'Email', value: _email),
                              const SizedBox(height: 12),
                              _field(
                                  _artistNameController, 'Artist / stage name'),
                              const SizedBox(height: 12),
                              _field(_fullNameController, 'Full name'),
                              const SizedBox(height: 12),
                              _field(_websiteController, 'Website'),
                              const SizedBox(height: 12),
                              _field(_soundcloudController, 'SoundCloud'),
                              const SizedBox(height: 12),
                              _field(_instagramController, 'Instagram'),
                              const SizedBox(height: 12),
                              _field(_spotifyController, 'Spotify'),
                              const SizedBox(height: 12),
                              _field(_appleMusicController, 'Apple Music'),
                              const SizedBox(height: 12),
                              _field(_youtubeController, 'YouTube'),
                              const SizedBox(height: 12),
                              _field(_tiktokController, 'TikTok'),
                              const SizedBox(height: 12),
                              _field(_facebookController, 'Facebook'),
                              const SizedBox(height: 12),
                              _field(_linktreeController, 'Linktree'),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _notesController,
                                decoration: const InputDecoration(
                                  labelText: 'Notes',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                                maxLines: 4,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passwordController,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  border: OutlineInputBorder(),
                                ),
                                obscureText: true,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPasswordController,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                  border: OutlineInputBorder(),
                                ),
                                obscureText: true,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                SelectableText(
                                  _error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error),
                                ),
                              ],
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _submitting ? null : _submit,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.save_rounded),
                                label: Text(_submitting
                                    ? 'Submitting...'
                                    : 'Complete registration'),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _readOnlyField({required String label, required String value}) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: SelectableText(value.isEmpty ? '-' : value),
    );
  }
}
