import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/core/api_client.dart';
import 'package:labelops_client/features/admin/admin_dashboard_delegate.dart';

class FakeAdminDashboardDelegate extends Fake implements AdminDashboardDelegate {
  FakeAdminDashboardDelegate({
    this.inboxThreads = const [],
    this.pendingReleases = const [],
  });

  final List<dynamic> inboxThreads;
  final List<dynamic> pendingReleases;

  int inboxLoadCalls = 0;
  int pendingLoadCalls = 0;
  int? openedThreadId;
  int? deletedThreadId;
  String? deletedArtistName;
  int? remindedPendingReleaseId;
  String? remindedArtistName;
  Map<String, dynamic>? messagedPendingRelease;

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
  Future<void> sendPendingReleaseReminder(int pendingReleaseId, String artistName) async {
    remindedPendingReleaseId = pendingReleaseId;
    remindedArtistName = artistName;
  }

  @override
  void showPendingReleaseMessageDialog(Map<String, dynamic> pendingRelease) {
    messagedPendingRelease = pendingRelease;
  }
}
