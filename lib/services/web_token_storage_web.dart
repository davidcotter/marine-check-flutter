import 'dart:html' as html;

const _key = 'dipreport_auth_token';

String? readToken() => html.window.localStorage[_key];

void writeToken(String token) {
  html.window.localStorage[_key] = token;
}

void deleteToken() {
  html.window.localStorage.remove(_key);
}
