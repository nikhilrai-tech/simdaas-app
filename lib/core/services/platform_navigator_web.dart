import 'dart:html' as html;

bool navigatorIsOnline() => html.window.navigator.onLine ?? true;
