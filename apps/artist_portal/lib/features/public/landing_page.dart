import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/api_client.dart';
import '../../core/demo_genre_options.dart';
import '../legal/privacy_policy_page.dart';
import '../legal/terms_of_use_page.dart';

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
  final _cityController = TextEditingController();
  final _messageController = TextEditingController();
  final _soundCloudLinkController = TextEditingController();

  bool _submitting = false;
  bool _consentToEmails = false;
  String? _feedback;
  bool _success = false;
  String? _selectedGenre;
  List<int>? _pickedMp3Bytes;
  String _pickedMp3Name = 'demo.mp3';

  @override
  void dispose() {
    _artistNameController.dispose();
    _contactNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _messageController.dispose();
    _soundCloudLinkController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final soundCloudLink = _soundCloudLinkController.text.trim();
    final hasLink = soundCloudLink.isNotEmpty;
    final hasFile = _pickedMp3Bytes != null && _pickedMp3Bytes!.isNotEmpty;
    if (!hasLink && !hasFile) {
      setState(() {
        _feedback = 'Please provide either a SoundCloud (or private track) link or upload an MP3 file.';
        _success = false;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    try {
      await widget.apiClient.submitPublicDemoWithLinkOrFile(
        artistName: _artistNameController.text,
        email: _emailController.text,
        consentToEmails: _consentToEmails,
        contactName: _contactNameController.text,
        phone: _phoneController.text,
        genre: _selectedGenre,
        city: _cityController.text,
        message: _messageController.text,
        soundCloudOrTrackLink: hasLink ? soundCloudLink : null,
        fileBytes: _pickedMp3Bytes,
        fileFilename: _pickedMp3Name,
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _feedback = 'Your demo was received successfully. We sent a confirmation email with a summary of your submission.';
        _submitting = false;
        _consentToEmails = false;
        _selectedGenre = null;
        _pickedMp3Bytes = null;
        _pickedMp3Name = 'demo.mp3';
      });
      _formKey.currentState!.reset();
      _artistNameController.clear();
      _contactNameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _cityController.clear();
      _messageController.clear();
      _soundCloudLinkController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _feedback = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  Future<void> _pickMp3() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.bytes == null || f.bytes!.isEmpty) {
      setState(() => _feedback = 'Could not read the file.');
      return;
    }
    final name = f.name.toLowerCase();
    if (!name.endsWith('.mp3')) {
      setState(() => _feedback = 'Only MP3 files are allowed.');
      return;
    }
    setState(() {
      _pickedMp3Bytes = f.bytes;
      _pickedMp3Name = f.name;
      _feedback = null;
    });
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
                    Image.asset(
                      'assets/images/zalmanim_logo.png',
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TermsOfUsePage(),
                        ),
                      ),
                      child: const Text('Terms of Use'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyPolicyPage(),
                        ),
                      ),
                      child: const Text('Privacy Policy'),
                    ),
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
                                  body: 'Your form enters the LM system with status demo. We also email you a submission summary, then the team reviews it and takes it into treatment.',
                                ),
                                const SizedBox(height: 14),
                                _FeatureCard(
                                  title: 'Mailing consent',
                                  body: 'Submitting a demo requires consent to join the Zalmanim mailing list and receive operational and marketing emails related to your submission and future updates.',
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
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: SelectableText(_feedback!),
                                          ),
                                          if (!_success)
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 20),
                                              onPressed: () => Clipboard.setData(
                                                ClipboardData(text: _feedback!),
                                              ),
                                              tooltip: 'Copy error',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 22),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBF6),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: const Color(0xFFD9CCBF)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Submission terms',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF231A14),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'By sending this demo, you agree to join the Zalmanim mailing list for marketing and operational emails related to your submission and future updates.',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: const Color(0xFF6B5D52),
                                            height: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        FormField<bool>(
                                          initialValue: _consentToEmails,
                                          validator: (value) {
                                            if (value == true) return null;
                                            return 'You must approve email consent before sending a demo.';
                                          },
                                          builder: (field) {
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(
                                                      color: field.hasError
                                                          ? const Color(0xFFB84C42)
                                                          : const Color(0xFFD9CCBF),
                                                    ),
                                                  ),
                                                  child: CheckboxListTile(
                                                    contentPadding: EdgeInsets.zero,
                                                    value: _consentToEmails,
                                                    controlAffinity: ListTileControlAffinity.leading,
                                                    title: const Text(
                                                      'I approve the use of my email for marketing and operational communication.',
                                                    ),
                                                    subtitle: const Text(
                                                      'This includes confirmation emails, status updates, and future label communication.',
                                                    ),
                                                    onChanged: (value) {
                                                      setState(() {
                                                        _consentToEmails = value ?? false;
                                                      });
                                                      field.didChange(value ?? false);
                                                    },
                                                  ),
                                                ),
                                                if (field.hasError) ...[
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    field.errorText!,
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: const Color(0xFFB84C42),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: [
                                      _field(_artistNameController, 'Artist name', width: 280, required: true),
                                      _field(_contactNameController, 'Contact name', width: 280),
                                      _field(_emailController, 'Email', width: 280, required: true, email: true),
                                      _field(_phoneController, 'Phone', width: 280),
                                      _genreField(width: 280),
                                      _field(_cityController, 'City', width: 280),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _field(
                                    _messageController,
                                    'Message',
                                    width: 576,
                                    maxLines: 5,
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    'Demo track (provide one or both)',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF231A14),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _field(
                                    _soundCloudLinkController,
                                    'SoundCloud or private track link',
                                    width: 576,
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _submitting ? null : _pickMp3,
                                        icon: const Icon(Icons.upload_file, size: 20),
                                        label: Text(_pickedMp3Bytes != null
                                            ? 'MP3: $_pickedMp3Name'
                                            : 'Upload MP3 only'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF1E1A17),
                                          side: const BorderSide(color: Color(0xFFD9CCBF)),
                                        ),
                                      ),
                                      if (_pickedMp3Bytes != null) ...[
                                        const SizedBox(width: 12),
                                        TextButton(
                                          onPressed: _submitting
                                              ? null
                                              : () => setState(() {
                                                    _pickedMp3Bytes = null;
                                                    _pickedMp3Name = 'demo.mp3';
                                                  }),
                                          child: const Text('Remove file'),
                                        ),
                                      ],
                                    ],
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

  Widget _genreField({required double width}) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: _selectedGenre,
        decoration: InputDecoration(
          labelText: 'Musical style',
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
        items: [
          for (final group in demoGenreGroups)
            ...[
              DropdownMenuItem<String>(
                enabled: false,
                value: '__$group',
                child: Text(
                  group,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final option in demoGenreOptions.where((item) => item.group == group))
                DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.value),
                ),
            ],
        ],
        onChanged: (value) => setState(() => _selectedGenre = value),
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
