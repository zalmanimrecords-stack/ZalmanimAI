import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.apiClient,
    required this.onSignIn,
  });

  final ApiClient apiClient;
  final VoidCallback onSignIn;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _formKey = GlobalKey<FormState>();
  final _artistNameController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _genreController = TextEditingController();
  final _cityController = TextEditingController();
  final _demoLinkController = TextEditingController();
  final _soundcloudController = TextEditingController();
  final _spotifyController = TextEditingController();
  final _messageController = TextEditingController();

  bool _submitting = false;
  String? _feedback;
  bool _success = false;

  @override
  void dispose() {
    _artistNameController.dispose();
    _contactNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genreController.dispose();
    _cityController.dispose();
    _demoLinkController.dispose();
    _soundcloudController.dispose();
    _spotifyController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    try {
      await widget.apiClient.submitPublicDemo(
        artistName: _artistNameController.text,
        email: _emailController.text,
        contactName: _contactNameController.text,
        phone: _phoneController.text,
        genre: _genreController.text,
        city: _cityController.text,
        message: _messageController.text,
        links: [
          _demoLinkController.text,
          _soundcloudController.text,
          _spotifyController.text,
        ],
        fields: {
          'demo_link': _demoLinkController.text.trim(),
          'soundcloud': _soundcloudController.text.trim(),
          'spotify': _spotifyController.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _feedback = 'Your demo was sent successfully. We will review it in the LM system.';
        _submitting = false;
      });
      _formKey.currentState!.reset();
      _artistNameController.clear();
      _contactNameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _genreController.clear();
      _cityController.clear();
      _demoLinkController.clear();
      _soundcloudController.clear();
      _spotifyController.clear();
      _messageController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _feedback = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = const Color(0xFFF4EFE8);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8F4EE), Color(0xFFE9DFD3)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                child: Row(
                  children: [
                    Text(
                      AppConfig.labelName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2D221A),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onSignIn,
                      child: const Text('Sign In'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Wrap(
                        spacing: 28,
                        runSpacing: 28,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        children: [
                          SizedBox(
                            width: 420,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Demo intake for artists.zalmanim.com',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'Send your demo directly to the Zalmanim LM system.',
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1F1712),
                                    height: 1.05,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Use this page to submit a new demo. If you already have an artist account, use Sign In to access your portal, uploads, demos, and media.',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: const Color(0xFF5C4D40),
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _FeatureCard(
                                  title: 'What happens next',
                                  body: 'Your form enters the LM system with status demo. The team can review it, move it forward, and send approval by email.',
                                ),
                                const SizedBox(height: 14),
                                _FeatureCard(
                                  title: 'For existing artists',
                                  body: 'Use Sign In in the top-right corner to enter your account and manage your ongoing material.',
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 620,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 28,
                                  offset: Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Demo submission form',
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF231A14),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Fill in the details below and we will route your submission into the system.',
                                    style: theme.textTheme.bodyLarge?.copyWith(color: const Color(0xFF6B5D52)),
                                  ),
                                  if (_feedback != null) ...[
                                    const SizedBox(height: 18),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: _success ? const Color(0xFFE7F6EA) : const Color(0xFFFBE9E8),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(_feedback!),
                                    ),
                                  ],
                                  const SizedBox(height: 22),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: [
                                      _field(_artistNameController, 'Artist name', width: 280, required: true),
                                      _field(_contactNameController, 'Contact name', width: 280),
                                      _field(_emailController, 'Email', width: 280, required: true, email: true),
                                      _field(_phoneController, 'Phone', width: 280),
                                      _field(_genreController, 'Genre', width: 280),
                                      _field(_cityController, 'City', width: 280),
                                      _field(_demoLinkController, 'Private demo link', width: 576, required: true),
                                      _field(_soundcloudController, 'SoundCloud link', width: 280),
                                      _field(_spotifyController, 'Spotify link', width: 280),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _field(
                                    _messageController,
                                    'Message',
                                    width: 576,
                                    maxLines: 5,
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                    onPressed: _submitting ? null : _submit,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF1E1A17),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: _submitting
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Text('Send Demo'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required double width,
    bool required = false,
    bool email = false,
    int maxLines = 1,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
        validator: (value) {
          final text = (value ?? '').trim();
          if (required && text.isEmpty) {
            return 'Required';
          }
          if (email && text.isNotEmpty && !text.contains('@')) {
            return 'Enter a valid email';
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD9CCBF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD9CCBF)),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5, color: const Color(0xFF5F564F)),
          ),
        ],
      ),
    );
  }
}
