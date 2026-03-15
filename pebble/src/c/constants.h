#pragma once

// Colors (Pebble GColor equivalents)
#define COLOR_BACKGROUND   GColorBlack
#define COLOR_STATION_NAME GColorWhite
#define COLOR_WALK_INFO    GColorLightGray
#define COLOR_SEPARATOR    GColorDarkGray
#define COLOR_MINUTES_GONE GColorDarkGray
#define COLOR_MINUTES_NOW  GColorYellow
#define COLOR_MINUTES_SOON GColorGreen
#define COLOR_DELAY        GColorOrange
#define COLOR_PLATFORM     GColorVividCerulean
#define COLOR_PLAT_CHANGED GColorRed
#define COLOR_SELECTION    GColorOxfordBlue
#define COLOR_SEL_ACCENT   GColorVividCerulean
#define COLOR_BAR_GREEN    GColorGreen
#define COLOR_BAR_LGREEN   GColorMintGreen
#define COLOR_BAR_RED      GColorRed
#define COLOR_BAR_AMBER    GColorChromeYellow
#define COLOR_BAR_GRAY     GColorDarkGray
#define COLOR_AHEAD        GColorGreen
#define COLOR_ON_TIME      GColorYellow
#define COLOR_BEHIND       GColorRed

// Timing
#define NORMAL_TICK_INTERVAL 5000    // ms
#define TRACKING_TICK_INTERVAL 1000  // ms
#define FETCH_COOLDOWN_NORMAL 30     // seconds
#define FETCH_COOLDOWN_TRACKING 10   // seconds

// Thresholds
#define MAX_STATIONS_PER_MODE 5
#define MAX_DEPARTURES 10
#define MAX_VISIBLE_DEPARTURES 4
#define CONSECUTIVE_ERROR_LIMIT 3
#define WALK_SPEED 83.0  // meters per minute
#define BAR_SCALE 3.0    // minutes mapped to half bar width

// Display
#define SCREEN_W 180
#define SCREEN_H 180
#define HEADER_H 36
#define ROW_H 32
#define BAR_H 10

// AppMessage commands
#define CMD_STATIONS_READY 1
#define CMD_DEPARTURE 2
#define CMD_DEPARTURES_DONE 3
#define CMD_GPS_UPDATE 4
#define CMD_ERROR 5
#define CMD_FETCH_DEPARTURES 6
#define CMD_REQUEST_STATIONS 7
