// Centralized configuration for the app

//prod
// const String apiBaseUrl = 'http://3.108.218.140:8000';
// stagging
const String apiBaseUrl = 'http://13.201.110.130:8000';

// Live WebSocket (telemetry, session_event, status_change, ...) is served by
// a separate daphne process on port 8001, on the SAME host as apiBaseUrl —
// both prod and staging follow this convention (see docker-compose*.yml's
// `api` vs `ws` services). Derived, not hardcoded: a stray hardcoded WS host
// here previously kept pointing at prod even while apiBaseUrl was switched to
// staging, so REST calls (and any manual refresh) showed the right data but
// nothing ever arrived live until you refreshed.
final String wsBaseUrl = 'ws://${Uri.parse(apiBaseUrl).host}:8001';

