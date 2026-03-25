part of 'artist_dashboard_page.dart';

extension ArtistDashboardPageUi on _ArtistDashboardPageState {
  Widget buildArtistDashboardPage(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final compact = _isCompactLayout(context);
    final horizontalPadding = compact ? 16.0 : 20.0;
    final releases = (dashboard?['releases'] as List<dynamic>? ?? const []);
    final tasks = (dashboard?['tasks'] as List<dynamic>? ?? const []);
    final pendingReleases =
        (dashboard?['pending_releases'] as List<dynamic>? ?? const []);
    final artistMap = dashboard?['artist'] as Map<String, dynamic>?;
    final artistName = artistMap?['name']?.toString() ?? 'Artist';

    if (!loading && error == null) {
      return Scaffold(
        appBar: AppBar(
          titleSpacing: compact ? 12 : null,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/images/zalmanim_logo.png',
                height: compact ? 26 : 32,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 4),
              AppVersionBadge(
                tooltipPrefix: 'Artist portal version',
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onPrimary
                    .withValues(alpha: 0.10),
                borderColor: Theme.of(context)
                    .colorScheme
                    .onPrimary
                    .withValues(alpha: 0.16),
                textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimary
                          .withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(ZalmanimIcons.logout),
              tooltip: 'Sign out',
              onPressed: () async {
                await widget.onLogout?.call();
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(icon: Icon(Icons.home_outlined), text: 'Home'),
              Tab(icon: Icon(Icons.send_outlined), text: 'Demos'),
              Tab(icon: Icon(Icons.library_music_outlined), text: 'Releases'),
              Tab(icon: Icon(Icons.mail_outline), text: 'Messages'),
              Tab(icon: Icon(Icons.folder_outlined), text: 'Media'),
              Tab(icon: Icon(Icons.person_outline), text: 'Account'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _homeTabChildren(
                context,
                primary: primary,
                artistName: artistName,
                releases: releases,
                tasks: tasks,
                pendingReleases: pendingReleases,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _demosTabChildren(
                context,
                primary: primary,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _releasesTabChildren(
                context,
                primary: primary,
                releases: releases,
                pendingReleases: pendingReleases,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _messagesTabChildren(
                context,
                primary: primary,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _mediaTabChildren(
                context,
                primary: primary,
                artistMap: artistMap,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _accountTabChildren(
                context,
                primary: primary,
                artistMap: artistMap,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: compact ? 12 : null,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/images/zalmanim_logo.png',
              height: compact ? 26 : 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 4),
            AppVersionBadge(
              tooltipPrefix: 'Artist portal version',
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              backgroundColor:
                  Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.10),
              borderColor:
                  Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.16),
              textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimary
                        .withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(ZalmanimIcons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await widget.onLogout?.call();
            },
          ),
        ],
      ),
      body: loading
          ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/zalmanim_logo.png',
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      CircularProgressIndicator(color: primary),
                    ],
                  ),
            )
          : error != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                          icon: const Icon(ZalmanimIcons.copy),
                          label: const Text('Copy error'),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, Color primary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: primary,
            ),
      ),
    );
  }

  Widget _tabListView(
    BuildContext context, {
    required List<Widget> children,
    required double horizontalPadding,
    required bool compact,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          compact ? 16 : 20,
          horizontalPadding,
          28,
        ),
        children: children,
      ),
    );
  }

  List<Widget> _homeTabChildren(
    BuildContext context, {
    required Color primary,
    required String artistName,
    required List<dynamic> releases,
    required List<dynamic> tasks,
    required List<dynamic> pendingReleases,
  }) {
    return [
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, $artistName',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the tabs under the logo to switch between Home, Demos, Releases, Messages, Media, and Account.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _summaryChip(context, primary, '${releases.length} releases'),
                _summaryChip(context, primary, '${demos.length} demos'),
                _summaryChip(
                    context, primary, '${pendingReleases.length} pending'),
                _summaryChip(context, primary, '${tasks.length} tasks'),
                _summaryChip(
                    context, primary, '${inboxThreads.length} messages'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionTitle(context, 'Jump to', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open a section without scrolling a long page.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: Icon(Icons.send_outlined, size: 18, color: primary),
                  label: const Text('Demos'),
                  onPressed: () => _tabController.animateTo(1),
                ),
                ActionChip(
                  avatar: Icon(Icons.library_music_outlined,
                      size: 18, color: primary),
                  label: const Text('Releases'),
                  onPressed: () => _tabController.animateTo(2),
                ),
                ActionChip(
                  avatar: Icon(Icons.mail_outline, size: 18, color: primary),
                  label: const Text('Messages'),
                  onPressed: () => _tabController.animateTo(3),
                ),
                ActionChip(
                  avatar: Icon(Icons.folder_outlined, size: 18, color: primary),
                  label: const Text('Media'),
                  onPressed: () => _tabController.animateTo(4),
                ),
                ActionChip(
                  avatar: Icon(Icons.person_outline, size: 18, color: primary),
                  label: const Text('Account'),
                  onPressed: () => _tabController.animateTo(5),
                ),
              ],
            ),
            if (pendingReleases.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'You have ${pendingReleases.length} pending release'
                '${pendingReleases.length == 1 ? '' : 's'} — review them in the Releases tab.',
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _tabController.animateTo(2),
                  icon: const Icon(Icons.library_music_outlined, size: 18),
                  label: const Text('Open Releases'),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'Tasks', primary),
      if (tasks.isEmpty)
        _emptyStateCard(context, primary, 'No tasks right now.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final t in tasks) ...[
                _taskTile(context, primary, t as Map<String, dynamic>),
                if (t != tasks.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'Campaign requests', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask the label to run a campaign for one of your releases.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: requestingCampaign ? null : _requestCampaign,
              child: Text(
                requestingCampaign
                    ? 'Sending...'
                    : 'Request campaign for a release',
              ),
            ),
            if (campaignRequests.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'My requests',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final request in campaignRequests)
                _campaignRequestTile(
                  context,
                  primary,
                  request as Map<String, dynamic>,
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _demosTabChildren(
    BuildContext context, {
    required Color primary,
  }) {
    return [
      _sectionTitle(context, 'Send demo', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your name and email are taken from your profile. Enter track name and musical style, then add a message or file.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: demoTrackNameController,
              decoration: const InputDecoration(
                labelText: 'Track name',
                hintText: 'Name of the track',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedDemoGenre,
              decoration: const InputDecoration(
                labelText: 'Musical style',
                border: OutlineInputBorder(),
              ),
              hint: const Text('Select style'),
              items: [
                for (final group in demoGenreGroups) ...[
                  DropdownMenuItem<String>(
                    enabled: false,
                    value: '__$group',
                    child: Text(
                      group,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final option
                      in demoGenreOptions.where((item) => item.group == group))
                    DropdownMenuItem<String>(
                      value: option.value,
                      child: Text(option.value),
                    ),
                ],
              ],
              onChanged: (value) => setState(() => _selectedDemoGenre = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: demoMessageController,
              decoration: const InputDecoration(
                labelText: 'Message (optional)',
                hintText: 'Describe your demo...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: submittingDemo ? null : _submitDemo,
              child: Text(
                submittingDemo
                    ? 'Submitting...'
                    : 'Pick file and submit demo',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'My demos', primary),
      if (demos.isEmpty)
        _emptyStateCard(context, primary, 'No demos yet.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final d in demos) ...[
                _demoTile(context, primary, d as Map<String, dynamic>),
                if (d != demos.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _releasesTabChildren(
    BuildContext context, {
    required Color primary,
    required List<dynamic> releases,
    required List<dynamic> pendingReleases,
  }) {
    return [
      _sectionTitle(context, 'Pending releases', primary),
      if (pendingReleases.isEmpty)
        _emptyStateCard(context, primary, 'No pending releases right now.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final r in pendingReleases) ...[
                _pendingReleaseTile(context, primary, r as Map<String, dynamic>),
                if (r != pendingReleases.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'My releases', primary),
      if (releases.isEmpty)
        _emptyStateCard(context, primary, 'No releases yet.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final r in releases) ...[
                _releaseTile(context, primary, r as Map<String, dynamic>),
                if (r != releases.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _messagesTabChildren(
    BuildContext context, {
    required Color primary,
  }) {
    return [
      _sectionTitle(context, 'Message the label', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send a message to the label. You will see replies here and can continue the conversation.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageToLabelController,
              decoration: const InputDecoration(
                labelText: 'Your message',
                hintText:
                    'Ideas, requests, complaints and any other topic are welcome. You are invited to contact us.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: sendingMessageToLabel ? null : _sendMessageToLabel,
              child: sendingMessageToLabel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send message'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'Your messages', primary),
      if (inboxThreads.isEmpty)
        _emptyStateCard(context, primary, 'No messages yet.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final t in inboxThreads) ...[
                _inboxThreadTile(context, primary, t as Map<String, dynamic>),
                if (t != inboxThreads.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _mediaTabChildren(
    BuildContext context, {
    required Color primary,
    required Map<String, dynamic>? artistMap,
  }) {
    return [
      _sectionTitle(context, 'My media', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your media folder (up to 50 MB total). Used: ${(mediaUsedBytes / (1024 * 1024)).toStringAsFixed(1)} / ${(mediaQuotaBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: uploadingMedia
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(ZalmanimIcons.upload),
              label: Text(
                uploadingMedia ? 'Uploading...' : 'Upload image or file',
              ),
              onPressed: uploadingMedia || mediaUsedBytes >= mediaQuotaBytes
                  ? null
                  : _uploadMedia,
            ),
            if (mediaUsedBytes >= mediaQuotaBytes)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Quota reached. Delete files to free space.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      if (mediaList.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _emptyStateCard(
            context,
            primary,
            'No media uploaded yet.',
          ),
        )
      else ...[
        const SizedBox(height: 12),
        _card(
          context,
          primary,
          Column(
            children: [
              for (final m in mediaList) ...[
                _mediaTile(context, primary, m as Map<String, dynamic>),
                if (m != mediaList.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      ],
      if (artistMap != null && artistMap['id'] != null) ...[
        const SizedBox(height: 24),
        _sectionTitle(context, 'Linktree images', primary),
        _card(
          context,
          primary,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pick a profile image and logo from your uploads (shown on your Linktree page).',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              _LinktreeImageRow(
                label: 'Profile image',
                currentMediaId: _profileImageMediaId,
                mediaList: mediaList,
                onSet: _setProfileImageForLinktree,
              ),
              const SizedBox(height: 8),
              _LinktreeImageRow(
                label: 'Logo',
                currentMediaId: _logoMediaId,
                mediaList: mediaList,
                onSet: _setLogoForLinktree,
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _accountTabChildren(
    BuildContext context, {
    required Color primary,
    required Map<String, dynamic>? artistMap,
  }) {
    return [
      _sectionTitle(context, 'My profile', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: profileNameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: profileFullNameController,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: profileWebsiteController,
              decoration: const InputDecoration(
                labelText: 'Website',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: profileNotesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            const Text(
              'Social & links (for your Linktree page)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ..._socialKeys.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: socialControllers[e.key],
                  decoration: InputDecoration(
                    labelText: e.value,
                    border: const OutlineInputBorder(),
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: savingProfile ? null : _saveProfile,
              child: Text(savingProfile ? 'Saving...' : 'Save profile'),
            ),
          ],
        ),
      ),
      if (artistMap != null && artistMap['id'] != null) ...[
        const SizedBox(height: 24),
        _sectionTitle(context, 'Linktree', primary),
        _card(
          context,
          primary,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My Linktree page',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final link = _linktreeUrlFor(artistMap['id']);
                  return InkWell(
                    onTap: () => openUrlOrCopy(context, link),
                    child: _isCompactLayout(context)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                link,
                                style: TextStyle(
                                  color: primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Icon(
                                Icons.open_in_new,
                                size: 18,
                                color: primary,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  link,
                                  style: TextStyle(
                                    color: primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.open_in_new,
                                size: 18,
                                color: primary,
                              ),
                            ],
                          ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Share this link for a styled page with all your links. Images are set under the Media tab.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 24),
      _sectionTitle(context, 'Security', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change portal password'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: changingPassword ? null : _changePassword,
              child: Text(changingPassword ? 'Updating...' : 'Change password'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),
    ];
  }

  Widget _emptyStateCard(BuildContext context, Color primary, String text) {
    return _card(
      context,
      primary,
      Text(
        text,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }

  Widget _campaignRequestTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final message = (item['message']?.toString().trim() ?? '');
    final subtitle = message.isEmpty
        ? item['status']?.toString() ?? ''
        : '${item['status']} - $message';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.campaign, color: primary),
      title: Text(item['release_title']?.toString() ?? 'No release'),
      subtitle: Text(subtitle),
    );
  }

  Widget _inboxThreadTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> thread,
  ) {
    final id = thread['id'] as int? ?? 0;
    final preview = (thread['last_message_preview'] ?? '').toString();
    final updated =
        (thread['last_message_at'] ?? thread['updated_at'] ?? '').toString();
    final hasReply = thread['has_label_reply'] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        hasReply ? Icons.mark_email_read : Icons.mail_outline,
        color: primary,
      ),
      title: Text(
        preview.isEmpty
            ? 'No subject'
            : preview.length > 60
                ? '${preview.substring(0, 60)}...'
                : preview,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        hasReply ? 'Replied - $updated' : updated,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      onTap: () => _openInboxThread(id),
    );
  }

  Widget _demoTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final msg = item['message']?.toString().trim() ?? '';
    final title = msg.isEmpty
        ? 'Demo #${item['id']}'
        : (msg.length > 50 ? '${msg.substring(0, 50)}...' : msg);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.send, color: primary),
      title: Text(title),
      subtitle: Text('Status: ${item['status']}'),
    );
  }

  Widget _pendingReleaseTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final comments = item['comments'] as List<dynamic>? ?? const [];
    final images = item['image_options'] as List<dynamic>? ?? const [];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.music, color: primary),
      title: Text((item['release_title'] ?? 'Pending release').toString()),
      subtitle: Text(
        'Status: ${(item['status'] ?? 'pending').toString()} - ${comments.length} message(s) - ${images.length} image option(s)',
      ),
      trailing: OutlinedButton(
        onPressed: () => _openPendingReleaseDialog(item),
        child: const Text('Open release page'),
      ),
    );
  }

  Widget _releaseTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.music, color: primary),
      title: Text(item['title'] as String),
      subtitle: Text('Status: ${item['status']}'),
    );
  }

  Widget _taskTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.taskAlt, color: primary),
      title: Text(item['title'] as String),
      subtitle: Text('${item['status']} | ${item['details']}'),
    );
  }

  Widget _mediaTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final id = item['id'] as int;
    final filename = item['filename'] as String? ?? 'file';
    final size = item['size_bytes'] as int? ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.folder, color: primary),
      title: Text(filename),
      subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(ZalmanimIcons.download),
            tooltip: 'Download',
            onPressed: () => _downloadMedia(id, filename),
          ),
          IconButton(
            icon: const Icon(ZalmanimIcons.delete),
            tooltip: 'Delete',
            onPressed: () => _deleteMedia(id),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(BuildContext context, Color primary, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _card(BuildContext context, Color primary, Widget child) {
    final compact = _isCompactLayout(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 16 : 12),
        side: BorderSide(color: primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: child,
      ),
    );
  }
}

/// Row for choosing a Linktree profile image or logo from the artist's media.
class _LinktreeImageRow extends StatelessWidget {
  const _LinktreeImageRow({
    required this.label,
    required this.currentMediaId,
    required this.mediaList,
    required this.onSet,
  });

  final String label;
  final int? currentMediaId;
  final List<dynamic> mediaList;
  final void Function(int mediaId) onSet;

  String? _filenameForId(int? id) {
    if (id == null) return null;
    for (final m in mediaList) {
      if (m is Map && (m['id'] as int?) == id) return m['filename']?.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentName = _filenameForId(currentMediaId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final button = TextButton.icon(
          onPressed: mediaList.isEmpty
              ? null
              : () async {
                  final id = await showDialog<int>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Set $label'),
                      content: SizedBox(
                        width: 320,
                        child: mediaList.isEmpty
                            ? const Text('Upload an image in My media first.')
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: mediaList.length,
                                itemBuilder: (_, i) {
                                  final m = mediaList[i] as Map<String, dynamic>;
                                  final mid = m['id'] as int?;
                                  final fn = m['filename']?.toString() ?? 'file';
                                  return ListTile(
                                    title: Text(fn),
                                    onTap: () => Navigator.of(ctx).pop(mid),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  );
                  if (id != null) onSet(id);
                },
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text('Set from my media'),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label: ${currentName ?? 'Not set'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 6),
              button,
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Text(
                '$label: ${currentName ?? 'Not set'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
            button,
          ],
        );
      },
    );
  }
}

