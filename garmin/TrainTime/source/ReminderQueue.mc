using Toybox.Application.Storage;
using Toybox.Lang;

// Single-slot outbox for "Remind on phone". phoneConnected only proves Bluetooth
// to Garmin Connect Mobile; a closed companion app drops transmits silently. The
// reminder is persisted here and retransmitted whenever an inbound phone message
// proves the app is listening, until the phone acks receipt by id. One slot, not
// a queue: both phone companions keep a single pending route, so last write wins.
module ReminderQueue {

    // Storage key: "pendingReminder" ->
    // { "payload" => Dictionary, "id" => String, "attempts" => Number, "queuedTs" => Number }

    const MAX_ATTEMPTS = 5;     // an old phone app never acks; stop retrying, saves are idempotent
    const GRACE_SEC = 120;      // keep retrying this long past departure
    const DRAIN_GAP_SEC = 5;    // the phone's alive-transition pushes arrive in a burst

    var mLastDrainTs = null;

    // Stable across retries, so the phone can dedupe and the ack can match
    function buildId(stationId, depTs, line) {
        return stationId + "|" + depTs + "|" + (line == null ? "" : line);
    }

    function isExpired(item, nowSec) {
        var payload = item["payload"];
        var depTs = payload != null ? payload["depTs"] : null;
        if (depTs == null) { return true; }
        return depTs + GRACE_SEC < nowSec;
    }

    function shouldRetry(item) {
        var attempts = item["attempts"];
        return attempts != null && attempts < MAX_ATTEMPTS;
    }

    function getPending() {
        var item = Storage.getValue("pendingReminder");
        if (item == null || !(item instanceof Lang.Dictionary)) { return null; }
        return item;
    }

    function hasPending() {
        return getPending() != null;
    }

    // The immediate transmit alongside enqueue counts as the first attempt
    function enqueue(payload, id, nowSec) {
        Storage.setValue("pendingReminder",
            { "payload" => payload, "id" => id, "attempts" => 1, "queuedTs" => nowSec });
    }

    // Phone confirmed receipt. Only a matching id clears the slot, so a stale ack
    // for a replaced reminder is a no-op. Returns whether it matched.
    function ack(id) {
        var item = getPending();
        if (item == null || id == null) { return false; }
        var pendingId = item["id"];
        if (pendingId != null && pendingId.equals(id)) {
            Storage.deleteValue("pendingReminder");
            return true;
        }
        return false;
    }

    // Drop a dead item (departed or attempt-capped) so it stops showing as waiting
    function prune(nowSec) {
        var item = getPending();
        if (item != null && (isExpired(item, nowSec) || !shouldRetry(item))) {
            Storage.deleteValue("pendingReminder");
        }
    }

    // Retransmit on evidence the phone app is alive (any inbound message).
    // Throttled so a burst of pushes triggers one retry, not one each.
    function drainIfDue(nowSec) {
        var item = getPending();
        if (item == null) { return; }
        if (isExpired(item, nowSec) || !shouldRetry(item)) {
            Storage.deleteValue("pendingReminder");
            return;
        }
        if (mLastDrainTs != null && nowSec - mLastDrainTs < DRAIN_GAP_SEC) { return; }
        mLastDrainTs = nowSec;
        item["attempts"] = item["attempts"] + 1;
        Storage.setValue("pendingReminder", item);
        PhoneSync.transmit(item["payload"]);
    }
}
