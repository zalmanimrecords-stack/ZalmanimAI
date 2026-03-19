import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/core/api_client.dart';
import 'package:labelops_client/features/admin/admin_dashboard_delegate.dart';

class FakeAdminDashboardDelegate extends Fake
    implements AdminDashboardDelegate {
  FakeAdminDashboardDelegate({
    this.inboxThreads = const [],
    this.pendingReleases = const [],
  });

  final List<dynamic> inboxThreads;
  final List<dynamic> pendingReleases;
  final TextEditingController _artistSearchController = TextEditingController();

  int inboxLoadCalls = 0;
  int pendingLoadCalls = 0;
  int? openedThreadId;
  int? deletedThreadId;
  String? deletedArtistName;
  int? remindedPendingReleaseId;
  String? remindedArtistName;
  int? archivedPendingReleaseId;
  String? archivedReleaseTitle;
  int? deletedPendingReleaseId;
  String? deletedReleaseTitle;
  Map<String, dynamic>? messagedPendingRelease;
  bool grooverInviteDialogShown = false;

  @override
  List<dynamic> get artistsList => const [];

  @override
  List<dynamic> get artistsListForReleases => const [];

  @override
  TextEditingController get artistSearchController => _artistSearchController;

  @override
  int get artistsSortColumn => 0;

  @override
  bool get artistsSortAsc => true;

  @override
  bool get artistsHasMore => false;

  @override
  bool get artistsLoadingMore => false;

  @override
  void setArtistsSort(int column, bool asc) {}

  @override
  Future<void> loadArtists() async {}

  @override
  Future<void> loadMoreArtists() async {}

  @override
  void showAddArtistDialog() {}

  @override
  void showEditArtistDialog(int id) {}

  @override
  void showSetArtistPasswordDialog(int artistId, String artistName) {}

  @override
  void sendArtistPortalInvite(
      int artistId, String artistName, String artistEmail) {}

  @override
  void sendArtistPortalInviteToAll() {}

  @override
  void sendArtistUpdateProfileInvite(
      int artistId, String artistName, String artistEmail) {}

  @override
  void showArtistDetailsDialog(int id) {}

  @override
  void removeArtist(int id, String name) {}

  @override
  void showMergeArtistsDialog() {}

  @override
  void showArtistReleases(int id, String name) {}

  @override
  ApiClient get apiClient => throw UnimplementedError();

  @override
  String get token => 'test-token';

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  void clearError() {}

  @override
  List<dynamic> get inboxThreadsList => inboxThreads;

  @override
  Future<void> loadInbox() async {
    inboxLoadCalls += 1;
  }

  @override
  void showInboxThreadDialog(int threadId) {
    openedThreadId = threadId;
  }

  @override
  Future<void> deleteInboxThread(int threadId, String artistName) async {
    deletedThreadId = threadId;
    deletedArtistName = artistName;
  }

  @override
  List<dynamic> get pendingReleasesList => pendingReleases;

  @override
  Future<void> loadPendingReleases({String? statusFilter}) async {
    pendingLoadCalls += 1;
  }

  @override
  Future<void> sendPendingReleaseReminder(
      int pendingReleaseId, String artistName) async {
    remindedPendingReleaseId = pendingReleaseId;
    remindedArtistName = artistName;
  }

  @override
  Future<void> archivePendingRelease(
      int pendingReleaseId, String releaseTitle,
      {String? statusFilter}) async {
    archivedPendingReleaseId = pendingReleaseId;
    archivedReleaseTitle = releaseTitle;
  }

  @override
  Future<void> deletePendingRelease(
      int pendingReleaseId, String releaseTitle,
      {String? statusFilter}) async {
    deletedPendingReleaseId = pendingReleaseId;
    deletedReleaseTitle = releaseTitle;
  }

  @override
  void showPendingReleaseMessageDialog(Map<String, dynamic> pendingRelease) {
    messagedPendingRelease = pendingRelease;
  }

  @override
  void showGrooverInviteDialog() {
    grooverInviteDialogShown = true;
  }
}
