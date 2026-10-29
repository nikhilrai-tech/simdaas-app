// Own, from-scratch offline map-tile cache -- NOT the usual
// flutter_map_tile_caching package, which is GPL v3 (using it would
// require this proprietary app's source to be released under the same
// license, or a paid commercial license purchased from its maintainer).
// This is plain Dart: a disk-backed ImageProvider for flutter_map's
// TileLayer, plus a bulk "download this area" helper. Deliberately simple
// -- no new dependency beyond what the app already has (http,
// path_provider, flutter_map, latlong2).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

// Android-safe cache dir, mirroring report_details_screen.dart's
// _scratchDirPath exactly: path_provider_android has a documented history
// of MissingPluginException on real devices in this app, worked around via
// MainActivity's own native MethodChannel instead of the plugin. kIsWeb is
// checked FIRST, before any dart:io symbol -- Platform/File/Directory all
// throw "Unsupported operation" on web.
const _androidCacheDirChannel = MethodChannel('com.simdaas.agrios/cache_dir');

Future<String?> _appCacheDirPath() async {
  if (kIsWeb) return null; // no meaningful disk cache on web; caller falls back to plain network
  if (Platform.isAndroid) {
    final path = await _androidCacheDirChannel.invokeMethod<String>('getCacheDir');
    if (path != null && path.isNotEmpty) return path;
    throw 'Android cache_dir channel returned no path';
  }
  final dir = await getTemporaryDirectory();
  return dir.path;
}

/// Reads/writes individual tile images from/to disk, by URL. One flat
/// directory -- the URL (which already encodes layer + z/x/y) is sanitized
/// directly into the filename, so no hashing/indexing is needed.
class OfflineTileCache {
  OfflineTileCache._();
  static final OfflineTileCache instance = OfflineTileCache._();

  Directory? _dir;

  Future<Directory?> _cacheDir() async {
    if (_dir != null) return _dir;
    final base = await _appCacheDirPath();
    if (base == null) return null;
    final dir = Directory('$base/map_tiles');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  String _filenameForUrl(String url) {
    final safe = url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    // URLs here are always well under the ~200 char range this produces,
    // but guard against any future, longer template anyway.
    return '${safe.length > 180 ? safe.substring(0, 180) : safe}.tile';
  }

  Future<File?> _fileForUrl(String url) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    return File('${dir.path}/${_filenameForUrl(url)}');
  }

  Future<bool> isTileCached(String url) async {
    final file = await _fileForUrl(url);
    if (file == null) return false;
    return file.exists();
  }

  /// Cache-first: serves the tile from disk if present, otherwise fetches
  /// it over the network and (best-effort) saves it for next time.
  Future<Uint8List> fetchTileBytes(String url) async {
    final file = await _fileForUrl(url);
    if (file != null && await file.exists()) {
      try {
        return await file.readAsBytes();
      } catch (_) {
        // Corrupt/partial cache file -- fall through and re-fetch.
      }
    }
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Tile fetch failed: HTTP ${response.statusCode} for $url');
    }
    final bytes = response.bodyBytes;
    if (file != null) {
      try {
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // Best-effort write -- still return the bytes either way.
      }
    }
    return bytes;
  }

  /// Total bytes currently on disk across all cached tiles, for a rough
  /// "X MB downloaded so far" readout. Best-effort -- returns 0 on any
  /// platform/IO issue rather than throwing.
  Future<int> cacheSizeBytes() async {
    try {
      final dir = await _cacheDir();
      if (dir == null || !await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}

/// flutter_map TileProvider backed by [OfflineTileCache] -- drop-in
/// replacement for the default NetworkTileProvider. On web (no disk cache
/// available here), falls back to a plain NetworkImage, same as before
/// this feature existed.
class CachedTileProvider extends TileProvider {
  // flutter_map's own NetworkTileProvider supports this (see its own
  // source) specifically so a tile pruned by fast panning/zooming, or a
  // whole TileLayer removed from the tree, stops being fetched instead of
  // running to completion in the background for no one. Without it, our
  // own providers kept working (and, for RetryingNetworkTileProvider
  // below, kept retrying through multi-second backoff waits) after the
  // farmer had already moved on -- directly competing with whatever the
  // base map was trying to load next, which is why switching back to the
  // base map after browsing historical dates felt slow.
  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final url = getTileUrl(coordinates, options);
    if (kIsWeb) return NetworkImage(url, headers: headers);
    return _DiskCachedTileImage(url, cancelLoading);
  }
}

class _DiskCachedTileImage extends ImageProvider<_DiskCachedTileImage> {
  final String url;
  final Future<void> cancelLoading;
  const _DiskCachedTileImage(this.url, this.cancelLoading);

  @override
  Future<_DiskCachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DiskCachedTileImage>(this);

  @override
  ImageStreamCompleter loadImage(_DiskCachedTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await Future.any<Uint8List>([
      OfflineTileCache.instance.fetchTileBytes(url),
      cancelLoading.then((_) => throw Exception('Tile no longer needed: $url')),
    ]);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is _DiskCachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

// ── Bulk "download this area for offline" ──────────────────────────────

/// Standard Slippy Map tile math (OSM/Google tile scheme): lat/lon -> the
/// tile x/y containing that point at a given zoom.
(int x, int y) _latLonToTileXY(double lat, double lon, int zoom) {
  final n = math.pow(2, zoom).toDouble();
  final x = ((lon + 180.0) / 360.0 * n).floor().clamp(0, (n - 1).toInt());
  final latRad = lat * math.pi / 180.0;
  final y = ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n)
      .floor()
      .clamp(0, (n - 1).toInt());
  return (x, y);
}

/// How many tile requests downloadRegion() would make for this bounds/zoom
/// range/template count -- shown to the user before they commit to a
/// download, same idea as the reference app's own size readout.
int estimateTileCount({
  required LatLngBounds bounds,
  required int minZoom,
  required int maxZoom,
  required int templateCount,
}) {
  var total = 0;
  for (var z = minZoom; z <= maxZoom; z++) {
    final (x1, y1) = _latLonToTileXY(bounds.north, bounds.west, z);
    final (x2, y2) = _latLonToTileXY(bounds.south, bounds.east, z);
    final minX = math.min(x1, x2), maxX = math.max(x1, x2);
    final minY = math.min(y1, y2), maxY = math.max(y1, y2);
    total += (maxX - minX + 1) * (maxY - minY + 1);
  }
  return total * templateCount;
}

class OfflineDownloadProgress {
  final int done;
  final int total;
  final int failed;
  const OfflineDownloadProgress({required this.done, required this.total, required this.failed});
}

/// Sequentially (deliberately not parallel -- this hits the same
/// undocumented Google tile endpoint every other map screen in the app
/// already uses live; a slow, one-at-a-time download is a gentler traffic
/// pattern than firing dozens of concurrent requests) fetches every tile
/// covering [bounds] across [minZoom]..[maxZoom] for each URL template in
/// [urlTemplates], writing each to disk via [OfflineTileCache]. Tiles
/// already cached are skipped. Reports progress via [onProgress] after
/// every tile (cached-skip or freshly-downloaded alike) so a progress bar
/// can track it; a failed tile is counted and skipped, never aborts the
/// whole download.
Future<OfflineDownloadProgress> downloadRegion({
  required LatLngBounds bounds,
  required int minZoom,
  required int maxZoom,
  required List<String> urlTemplates,
  void Function(OfflineDownloadProgress progress)? onProgress,
  bool Function()? isCancelled,
}) async {
  final total = estimateTileCount(
    bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, templateCount: urlTemplates.length,
  );
  var done = 0, failed = 0;
  void report() => onProgress?.call(OfflineDownloadProgress(done: done, total: total, failed: failed));
  report();

  for (final template in urlTemplates) {
    for (var z = minZoom; z <= maxZoom; z++) {
      final (x1, y1) = _latLonToTileXY(bounds.north, bounds.west, z);
      final (x2, y2) = _latLonToTileXY(bounds.south, bounds.east, z);
      final minX = math.min(x1, x2), maxX = math.max(x1, x2);
      final minY = math.min(y1, y2), maxY = math.max(y1, y2);
      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          if (isCancelled?.call() ?? false) {
            return OfflineDownloadProgress(done: done, total: total, failed: failed);
          }
          final url = template
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y');
          try {
            if (!await OfflineTileCache.instance.isTileCached(url)) {
              await OfflineTileCache.instance.fetchTileBytes(url);
            }
          } catch (e) {
            failed++;
            debugPrint('downloadRegion: tile fetch failed for $url: $e');
          }
          done++;
          report();
        }
      }
    }
  }
  return OfflineDownloadProgress(done: done, total: total, failed: failed);
}

/// Pads a polygon's bounding box outward so a small amount of panning past
/// the exact plot boundary still hits the cache (a strict exact-boundary
/// download would leave the cache edge visibly "pop" to live tiles the
/// moment you pan slightly outside the plot while viewing it).
LatLngBounds paddedBoundsForPoints(List<LatLng> points, {double paddingFraction = 0.25}) {
  final bounds = LatLngBounds.fromPoints(points);
  final latPad = (bounds.north - bounds.south) * paddingFraction;
  final lngPad = (bounds.east - bounds.west) * paddingFraction;
  return LatLngBounds(
    LatLng(bounds.south - latPad, bounds.west - lngPad),
    LatLng(bounds.north + latPad, bounds.east + lngPad),
  );
}
