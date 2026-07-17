enum AppRole { bidan, pasien, admin }

extension AppRoleLabel on AppRole {
  String get label => switch (this) {
    AppRole.bidan => 'Bidan',
    AppRole.pasien => 'Pasien',
    AppRole.admin => 'Admin',
  };

  String get homeLocation => switch (this) {
    AppRole.bidan => '/bidan/home',
    AppRole.pasien => '/pasien/home',
    AppRole.admin => '/admin/facilities',
  };

  static AppRole? fromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return AppRole.values.where((role) => role.name == normalized).firstOrNull;
  }
}

class AppProfile {
  const AppProfile({
    required this.userId,
    required this.email,
    required this.role,
    this.displayName,
  });

  final String userId;
  final String? email;
  final AppRole role;
  final String? displayName;
}
