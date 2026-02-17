void navigateToAuthUrl(String url) {
  throw UnsupportedError('navigateToAuthUrl is only supported on web');
}

String? getAuthTokenFromUrl() {
  return null;
}

void cleanAuthTokenFromUrl() {
  // no-op on non-web platforms
}
