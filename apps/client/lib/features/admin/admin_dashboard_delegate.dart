import 'package:flutter/material.dart';

import '../../core/api_client.dart';

/// Interface for admin dashboard tab widgets to access data and actions.
/// Implemented by [AdminDashboardPage] state.
abstract class AdminDashboardDelegate {
  ApiClient get apiClient;
  String get token;

  bool get isLoading;
  String? get errorMessage;
  void clearError();

  // Artists
  List<dynamic> get artistsList;
  List<dynamic> get artistsListForReleases;
  TextEditingController get artistSearchController;
  int get artistsSortColumn;
  bool get artistsSortAsc;
  bool get artistsHasMore;
  bool get artistsLoadingMore;
  void setArtistsSort(int column, bool asc);
  Future<void> loadArtists();
  Future<void> loadMoreArtists();
  void showAddArtistDialog();
  void showEditArtistDialog(int id);
  void showSetArtistPasswordDialog(int artistId, String artistName);
  void sendArtistPortalInvite(
      int artistId, String artistName, String artistEmail);
  void sendArtistPortalInviteToAll();
  void sendArtistUpdateProfileInvite(
      int artistId, String artistName, String artistEmail);
  void showArtistDetailsDialog(int id);
  void removeArtist(int id, String name);
  void showMergeArtistsDialog();
  void showArtistReleases(int id, String name);
  void showGrooverInviteDialog();

  // Demos
  List<dynamic> get demoSubmissionsList;
  Future<void> loadDemoSubmissions();
  void showDemoDetailsDialog(Map<String, dynamic> submission);
  void showApproveDemoDialog(Map<String, dynamic> submission);
  void updateDemoStatus(Map<String, dynamic> submission, String status);
  Future<void> deleteDemoSubmission(Map<String, dynamic> submission);

  // Releases + catalog
  List<dynamic> get adminReleasesList;
  List<dynamic> get catalogTracksList;
  TextEditingController get releasesSearchController;
  int? get catalogSortColumnIndex;
  bool get catalogSortAsc;
  int get releasesSortBy;
  bool get releasesSortAsc;
  bool get releasesPageHasMore;
  bool get releasesPageLoadingMore;
  void setCatalogSort(int? column, bool asc);
  void setReleasesSort(int by, bool asc);
  Future<void> loadReleases();
  Future<void> loadMoreReleasesPage();
  void importCatalogCsv();
  void syncReleasesFromCatalog();
  void syncOriginalArtistsFromArtists();
  void createMissingOriginalArtists();
  void showSetArtistsDialog(Map<String, dynamic> release);
  void prepareCampaignFromRelease(
      int artistId, String artistName, Map<String, dynamic> release);

  // Campaigns
  List<dynamic> get campaignsList;
  List<dynamic> get connectionsList;
  List<dynamic> get hubConnectorsList;
  int get campaignsSortBy;
  bool get campaignsSortAsc;
  bool get campaignsHasMore;
  bool get campaignsLoadingMore;
  void setCampaignsSort(int by, bool asc);
  Future<void> loadCampaigns();
  Future<void> loadMoreCampaigns();
  void showCreateCampaignDialog(
      {String? initialName,
      String? initialTitle,
      String? initialBody,
      int? initialArtistId});
  void showEditCampaignDialog(Map<String, dynamic> campaign);
  void showScheduleCampaignDialog(int campaignId);
  void cancelCampaignSchedule(int id);
  void deleteCampaign(int id, String name);

  // Campaign requests (from artists)
  List<dynamic> get campaignRequestsList;
  Future<void> loadCampaignRequests({String? statusFilter});
  void updateCampaignRequestStatus(int requestId, String status,
      {String? adminNotes});

  // Pending for release (tracks with full details submitted, waiting for treatment)
  List<dynamic> get pendingReleasesList;
  Future<void> loadPendingReleases({String? statusFilter});
  Future<void> sendPendingReleaseReminder(
      int pendingReleaseId, String artistName);
  void showPendingReleaseMessageDialog(Map<String, dynamic> pendingRelease);

  // Inbox (artist messages to label; admin can reply, reply is emailed to artist)
  List<dynamic> get inboxThreadsList;
  Future<void> loadInbox();
  void showInboxThreadDialog(int threadId);
  Future<void> deleteInboxThread(int threadId, String artistName);

  // Audience / email lists
  List<dynamic> get audiencesList;
  List<dynamic> get audienceSubscribersList;
  int? get selectedAudienceId;
  Future<void> loadAudiences();
  Future<void> selectAudience(int id);
  void showCreateAudienceDialog();
  void importMailchimpAudienceCsv();
  void showEditAudienceDialog(Map<String, dynamic> audience);
  void showAddAudienceSubscriberDialog();
  void showEditAudienceSubscriberDialog(Map<String, dynamic> subscriber);
  void toggleAudienceSubscriberStatus(Map<String, dynamic> subscriber);
  // Reports
  void showArtistRemindersReport(BuildContext context);
  void showSignedInArtistsReport(BuildContext context);
  void showSendEmailToReportArtistsDialog(BuildContext context,
      List<dynamic> reportList, List<int> selectedIndices);
  void showArtistReminderMailSettingsDialog(BuildContext context);

  // Admin users (admin-only)
  List<dynamic> get usersList;
  Future<void> loadUsers();
  void showAddUserDialog();
  void showEditUserDialog(Map<String, dynamic> user);
  void updateUserActive(Map<String, dynamic> user, bool isActive);

  void showErrorSnackBar(String message);

  Future<void> load();
}
