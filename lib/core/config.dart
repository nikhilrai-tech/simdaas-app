// Centralized configuration for the app

const String _prodApiBaseUrl = 'http://3.108.218.140:8000';

//prod
// const String apiBaseUrl = 'http://3.108.218.140:8000';
// stagging
const String apiBaseUrl = 'http://13.201.110.130:8000';

// Derived from apiBaseUrl above rather than a second toggle — so a build
// switched to staging automatically shows the STAGING ribbon (see main.dart)
// with no extra step to remember, and no risk of it staying prod-labelled
// after apiBaseUrl was switched (or vice versa).
const bool isStaging = apiBaseUrl != _prodApiBaseUrl;

// Live WebSocket (telemetry, session_event, status_change, ...) is served by
// a separate daphne process on port 8001, on the SAME host as apiBaseUrl —
// both prod and staging follow this convention (see docker-compose*.yml's
// `api` vs `ws` services). Derived, not hardcoded: a stray hardcoded WS host
// here previously kept pointing at prod even while apiBaseUrl was switched to
// staging, so REST calls (and any manual refresh) showed the right data but
// nothing ever arrived live until you refreshed.
final String wsBaseUrl = 'ws://${Uri.parse(apiBaseUrl).host}:8001';

