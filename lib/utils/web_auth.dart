import 'dart:html' as html;

void navigateToAuthUrl(String url) {
  html.window.location.href = url;
}

String? getAuthTokenFromUrl() {
  final uri = Uri.parse(html.window.location.href);
  return uri.queryParameters['auth_token'];
}

void cleanAuthTokenFromUrl() {
  final uri = Uri.parse(html.window.location.href);
  final newParams = Map<String, String>.from(uri.queryParameters)
    ..remove('auth_token');
  final newUri = uri.replace(
    queryParameters: newParams.isEmpty ? null : newParams,
  );
  html.window.history.replaceState(null, '', newUri.toString());
}
