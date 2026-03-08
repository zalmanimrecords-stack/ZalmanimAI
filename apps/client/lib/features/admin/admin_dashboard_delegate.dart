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
  TextEditingController get artistSearchController;
  int get artistsSortColumn;
  bool get artistsSortAsc;
  void setArtistsSort(int column, bool asc);
  Future<void> loadArtists();
  void showAddArtistDialog();
  void showEditArtistDialog(int id);
  void showArtistDetailsDialog(int id);
  void removeArtist(int id, String name);
  void showMergeArtistsDialog();
  void showArtistReleases(int id, String name);

  // Releases + catalog
  List<dynamic> get adminReleasesList;
  List<dynamic> get catalogTracksList;
  List<dynamic> get artistsListForReleases;
  TextEditingController get releasesSearchController;
  int? get catalogSortColumnIndex;
  bool get catalogSortAsc;
  void setCatalogSort(int? column, bool asc);
  int get releasesSortBy;
  bool get releasesSortAsc;
  void setReleasesSort(int by, bool asc);
  Future<void> loadReleases();
  void importCatalogCsv();
  void syncReleasesFromCatalog();
  void syncOriginalArtistsFromArtists();
  void createMissingOriginalArtists();
  void showSetArtistsDialog(Map<String, dynamic> release);
  void prepareCampaignFromRelease(int artistId, String artistName, Map<String, dynamic> release);

  // Campaigns (connections/hubConnectors are empty until API is added)
  List<dynamic> get campaignsList;
  List<dynamic> get connectionsList;
  List<dynamic> get hubConnectorsList;
  int get campaignsSortBy;
  bool get campaignsSortAsc;
  void setCampaignsSort(int by, bool asc);
  Future<void> loadCampaigns();
  void showCreateCampaignDialog({String? initialName, String? initialTitle, String? initialBody, int? initialArtistId});
  void showEditCampaignDialog(Map<String, dynamic> campaign);
  void showScheduleCampaignDialog(int campaignId);
  void cancelCampaignSchedule(int id);
  void deleteCampaign(int id, String name);

  // Reports
  void showArtistRemindersReport(BuildContext context);
  void showSendEmailToReportArtistsDialog(BuildContext context, List<dynamic> reportList, List<int> selectedIndices);

  void showErrorSnackBar(String message);

  /// Full load (all tabs). Used by RefreshIndicator and initial load.
  Future<void> load();
}
