import 'package:flutter/material.dart';

import '../../core/api_client.dart';

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
  static const List<_GenreOption> _genreOptions = [
    _GenreOption('House', 'House'),
    _GenreOption('House', 'House / Acid'),
    _GenreOption('House', 'House / Soulful'),
    _GenreOption('House', 'Jackin House'),
    _GenreOption('House', 'Organic House'),
    _GenreOption('House', 'Progressive House'),
    _GenreOption('House', 'Afro House'),
    _GenreOption('House', 'Afro House / Afro Latin'),
    _GenreOption('House', 'Afro House / Afro Melodic'),
    _GenreOption('House', 'Afro House / 3Step'),
    _GenreOption('House', 'Tech House'),
    _GenreOption('House', 'Tech House / Latin Tech'),
    _GenreOption('House', 'Melodic House & Techno / Melodic House'),
    _GenreOption('Techno', 'Hard Techno'),
    _GenreOption('Techno', 'Techno (Peak Time / Driving)'),
    _GenreOption('Techno', 'Techno / Peak Time'),
    _GenreOption('Techno', 'Techno / Driving'),
    _GenreOption('Techno', 'Techno / Psy-Techno'),
    _GenreOption('Techno', 'Techno (Raw / Deep / Hypnotic)'),
    _GenreOption('Techno', 'Techno / Raw'),
    _GenreOption('Techno', 'Techno / Deep / Hypnotic'),
    _GenreOption('Techno', 'Techno / Dub'),
    _GenreOption('Techno', 'Techno / EBM'),
    _GenreOption('Techno', 'Techno / Broken'),
    _GenreOption('Techno', 'Melodic House & Techno / Melodic Techno'),
    _GenreOption('Trance', 'Trance (Main Floor)'),
    _GenreOption('Trance', 'Trance / Progressive Trance'),
    _GenreOption('Trance', 'Trance / Tech Trance'),
    _GenreOption('Trance', 'Trance / Uplifting Trance'),
    _GenreOption('Trance', 'Trance / Vocal Trance'),
    _GenreOption('Trance', 'Trance / Hard Trance'),
    _GenreOption('Trance', 'Trance (Raw / Deep / Hypnotic)'),
    _GenreOption('Trance', 'Trance / Raw Trance'),
    _GenreOption('Trance', 'Trance / Deep Trance'),
    _GenreOption('Trance', 'Trance / Hypnotic Trance'),
    _GenreOption('Trance', 'Psy-Trance'),
    _GenreOption('Trance', 'Psy-Trance / Full-On'),
    _GenreOption('Trance', 'Psy-Trance / Progressive Psy'),
    _GenreOption('Trance', 'Psy-Trance / Psychedelic'),
    _GenreOption('Trance', 'Psy-Trance / Dark & Forest'),
    _GenreOption('Trance', 'Psy-Trance / Goa Trance'),
    _GenreOption('Trance', 'Psy-Trance / Psycore & Hi-Tech'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _artistNameController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _messageController = TextEditingController();

  bool _submitting = false;
  bool _consentToEmails = false;
  String? _feedback;
  bool _success = false;
  String? _selectedGenre;

  @override
  void dispose() {
    _artistNameController.dispose();
    _contactNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
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
        consentToEmails: _consentToEmails,
        contactName: _contactNameController.text,
        phone: _phoneController.text,
        genre: _selectedGenre,
        city: _cityController.text,
        message: _messageController.text,
        fields: {
          'consent_copy':
              'I agree to join the Zalmanim mailing list and receive marketing and operational emails related to my demo submission.',
        },
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _feedback = 'Your demo was received successfully. We sent a confirmation email with a summary of your submission.';
        _submitting = false;
        _consentToEmails = false;
        _selectedGenre = null;
      });
      _formKey.currentState!.reset();
      _artistNameController.clear();
      _contactNameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _cityController.clear();
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
                    Image.asset(
                      'assets/images/zalmanim_logo.png',
                      height: 40,
                      fit: BoxFit.contain,
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
                                      child: Text(_feedback!),
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
          for (final group in {'House', 'Techno', 'Trance'})
            ...[
              DropdownMenuItem<String>(
                enabled: false,
                value: '__$group',
                child: Text(
                  group,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final option in _genreOptions.where((item) => item.group == group))
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

class _GenreOption {
  const _GenreOption(this.group, this.value);

  final String group;
  final String value;
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
