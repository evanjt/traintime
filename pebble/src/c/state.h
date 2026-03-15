#pragma once

#include <pebble.h>
#include "constants.h"

// Transport modes
typedef enum {
    MODE_TRAIN = 0,
    MODE_BUS = 1,
    MODE_TRAM = 2,
    MODE_SPECIAL = 3,
    MODE_COUNT = 4
} TransportMode;

// GPS quality
typedef enum {
    GPS_UNAVAILABLE = 0,
    GPS_POOR = 1,
    GPS_GOOD = 2
} GPSQuality;

// Station
typedef struct {
    char id[64];
    char name[64];
    int dist;        // meters
    bool has_data;
} Station;

// Departure
typedef struct {
    char destination[64];
    int minutes_until;
    int departure_timestamp;
    int delay;
    char platform[8];
    bool platform_changed;
    char line_number[8];
    bool has_data;
} Departure;

// Focused departure for tracking
typedef struct {
    char destination[64];
    int departure_timestamp;
    int delay;
    char platform[8];
    bool platform_changed;
    bool active;
} FocusedDeparture;

// App state
typedef struct {
    int state;  // 0=station, 1=cursor, 2=tracking, 3=inactive

    // Stations per mode
    Station stations[MODE_COUNT][MAX_STATIONS_PER_MODE];
    int station_count[MODE_COUNT];
    int station_index;

    // Current mode + available
    TransportMode current_mode;
    bool mode_available[MODE_COUNT];

    // Departures
    Departure departures[MAX_DEPARTURES];
    int departure_count;

    // Cursor (state 1)
    int cursor_index;

    // Tracking (state 2)
    FocusedDeparture focused;

    // GPS
    GPSQuality gps_quality;
    int walk_dist;  // meters

    // Status
    char status[64];

    // Internal
    int consecutive_errors;
    time_t last_fetch_time;
    time_t last_vibe_tick;
    time_t last_interaction_time;
} AppState;

// Global state
extern AppState g_state;

// Functions
void state_init(void);
void state_clear_stations(void);
void state_rebuild_modes(void);
Station* state_current_station(void);
void state_select_mode(TransportMode mode);
void state_cycle_mode(void);
void state_select_departure(int index);
void state_enter_inactive(void);
void state_resume(void);
void state_exit_to_station(void);
int state_walk_minutes(int dist_meters);
char* state_format_walk_info(int dist_meters);
int state_seconds_until(int timestamp);
double state_minutes_until_f(int timestamp);
