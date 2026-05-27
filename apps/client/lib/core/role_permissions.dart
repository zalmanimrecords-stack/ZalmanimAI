/// Mirrors server [ROLE_PERMISSIONS] for UI gating when permissions are not stored in session.
const Map<String, Set<String>> rolePermissions = {
  'admin': {
    'artists:read',
    'artists:write',
    'releases:read',
    'releases:write',
    'campaigns:read',
    'campaigns:write',
    'reports:read',
    'settings:read',
    'settings:write',
    'users:read',
    'users:write',
  },
  'manager': {
    'artists:read',
    'artists:write',
    'releases:read',
    'releases:write',
    'campaigns:read',
    'campaigns:write',
    'reports:read',
    'settings:read',
    'users:read',
  },
  'artist': {
    'artist:self',
    'releases:self',
  },
};

bool roleHasPermission(String role, String permission) {
  if (role == 'admin') return true;
  return rolePermissions[role]?.contains(permission) ?? false;
}
