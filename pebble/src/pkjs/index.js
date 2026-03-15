var API_BASE = 'https://api.traintime.ch';
var API_KEY = 'YOUR_API_KEY_HERE'; // Replaced by CI

var lastSearchLat = null;
var lastSearchLon = null;
var watchId = null;

// Movement thresholds (same as Garmin/iOS)
var MOVEMENT_LAT = 0.0045;
var MOVEMENT_LON = 0.006;

// Haversine distance (flat-earth, matches all platforms)
function haversineDistance(lat1, lon1, lat2, lon2) {
  var dLat = (lat2 - lat1) * 111000.0;
  var dLon = (lon2 - lon1) * 75700.0;
  return Math.sqrt(dLat * dLat + dLon * dLon);
}

function hasMovedSignificantly(lat1, lon1, lat2, lon2) {
  return Math.abs(lat2 - lat1) > MOVEMENT_LAT || Math.abs(lon2 - lon1) > MOVEMENT_LON;
}

// Swiss bounds
function isInSwitzerland(lat, lon) {
  return lat >= 45.8 && lat <= 47.8 && lon >= 5.9 && lon <= 10.5;
}

// Send GPS quality to watch
function sendGPSQuality(quality) {
  Pebble.sendAppMessage({
    'CMD': 4, // CMD_GPS_UPDATE
    'GPS_QUALITY': quality
  });
}

// Fetch stations from API
function fetchStations(lat, lon) {
  var url = API_BASE + '/v1/nearby?lat=' + lat + '&lon=' + lon;

  var xhr = new XMLHttpRequest();
  xhr.open('GET', url, true);
  xhr.setRequestHeader('X-API-Key', API_KEY);
  xhr.timeout = 30000;

  xhr.onload = function() {
    if (xhr.status === 429) {
      sendError('Rate limited');
      return;
    }
    if (xhr.status !== 200) {
      sendError('HTTP ' + xhr.status);
      return;
    }

    try {
      var data = JSON.parse(xhr.responseText);
      var modes = ['train', 'bus', 'tram', 'special'];
      var modeValues = [0, 1, 2, 3];

      for (var m = 0; m < modes.length; m++) {
        var stations = data[modes[m]];
        if (!stations) continue;

        for (var i = 0; i < Math.min(stations.length, 5); i++) {
          var s = stations[i];
          if (!s.id) continue;

          // Calculate distance if coords available
          var dist = 0;
          if (s.dist) {
            dist = Math.round(s.dist);
          } else if (s.lat && s.lon) {
            dist = Math.round(haversineDistance(lat, lon, s.lat, s.lon));
          }

          Pebble.sendAppMessage({
            'CMD': 1, // CMD_STATIONS_READY
            'STATION_NAME': s.name || 'Unknown',
            'STATION_ID': s.id,
            'STATION_DIST': dist,
            'STATION_MODE': modeValues[m]
          });
        }
      }

      lastSearchLat = lat;
      lastSearchLon = lon;
    } catch (e) {
      sendError('Parse error');
    }
  };

  xhr.onerror = function() {
    sendError('No connection');
  };

  xhr.ontimeout = function() {
    sendError('Timeout');
  };

  xhr.send();
}

// Fetch departures for a station
function fetchDepartures(stationId) {
  var url = API_BASE + '/v1/departures?id=' + encodeURIComponent(stationId) + '&limit=10';

  var xhr = new XMLHttpRequest();
  xhr.open('GET', url, true);
  xhr.setRequestHeader('X-API-Key', API_KEY);
  xhr.timeout = 30000;

  xhr.onload = function() {
    if (xhr.status === 429) {
      sendError('Rate limited');
      return;
    }
    if (xhr.status !== 200) {
      sendError('HTTP ' + xhr.status);
      return;
    }

    try {
      var data = JSON.parse(xhr.responseText);
      var departures = data.departures || [];
      var count = Math.min(departures.length, 10);
      var now = Math.floor(Date.now() / 1000);

      for (var i = 0; i < count; i++) {
        var dep = departures[i];
        var destination = dep.to || '?';
        var category = dep.category || '';
        var number = dep.number || '';
        var lineNumber = (category === 'B' || category === 'T' || category === 'NFB' || category === 'NFT' || category === 'M') ? number : '';
        var platform = dep.platform || '';
        var platformChanged = dep.platformChanged ? 1 : 0;
        var depTs = dep.departure || 0;
        var minutesUntil = depTs > 0 ? Math.floor((depTs - now) / 60) : -1;
        var delay = (dep.delay && dep.delay > 0) ? dep.delay : 0;

        Pebble.sendAppMessage({
          'CMD': 2, // CMD_DEPARTURE
          'DEP_DESTINATION': destination,
          'DEP_MINUTES': minutesUntil,
          'DEP_TIMESTAMP': depTs,
          'DEP_DELAY': delay,
          'DEP_PLATFORM': platform,
          'DEP_PLATFORM_CHANGED': platformChanged,
          'DEP_LINE_NUMBER': lineNumber,
          'DEP_INDEX': i,
          'DEP_COUNT': count
        });
      }

      // Signal departures done
      Pebble.sendAppMessage({
        'CMD': 3 // CMD_DEPARTURES_DONE
      });
    } catch (e) {
      sendError('Parse error');
    }
  };

  xhr.onerror = function() {
    sendError('No connection');
  };

  xhr.ontimeout = function() {
    sendError('Timeout');
  };

  xhr.send();
}

function sendError(msg) {
  Pebble.sendAppMessage({
    'CMD': 5, // CMD_ERROR
    'ERROR_MSG': msg
  });
}

// Handle messages from watch
Pebble.addEventListener('appmessage', function(e) {
  var dict = e.payload;

  if (dict.CMD === 7) { // CMD_REQUEST_STATIONS
    if (lastSearchLat !== null && lastSearchLon !== null) {
      fetchStations(lastSearchLat, lastSearchLon);
    }
  } else if (dict.CMD === 6) { // CMD_FETCH_DEPARTURES
    var stationId = dict.FETCH_STATION_ID;
    if (stationId) {
      fetchDepartures(stationId);
    }
  }
});

// Start GPS when app opens
Pebble.addEventListener('ready', function() {
  console.log('TrainTime JS ready');

  var options = {
    enableHighAccuracy: true,
    maximumAge: 10000,
    timeout: 30000
  };

  watchId = navigator.geolocation.watchPosition(
    function(pos) {
      var lat = pos.coords.latitude;
      var lon = pos.coords.longitude;
      var accuracy = pos.coords.accuracy;

      // Send GPS quality
      var quality = 0; // unavailable
      if (accuracy >= 0 && accuracy <= 30) quality = 2; // good
      else if (accuracy > 30 && accuracy <= 100) quality = 1; // poor

      sendGPSQuality(quality);

      if (!isInSwitzerland(lat, lon)) {
        sendError('Not in Switzerland');
        return;
      }

      // Check if moved significantly
      if (lastSearchLat === null || lastSearchLon === null ||
          hasMovedSignificantly(lastSearchLat, lastSearchLon, lat, lon)) {
        fetchStations(lat, lon);
      }
    },
    function(err) {
      sendGPSQuality(0);
      sendError('GPS error');
    },
    options
  );
});

// Cleanup on close
Pebble.addEventListener('unload', function() {
  if (watchId !== null) {
    navigator.geolocation.clearWatch(watchId);
  }
});
