using Toybox.Test;
using Toybox.Application.Storage;

// Unit tests for the reminder outbox. Built only with `monkeyc -t` and excluded
// from shipping builds. PhoneSync.transmit is inert here (never activated), so
// drainIfDue exercises the storage logic without touching the sim's phone bridge.

// The runner executes every (:test) function, so no payload helper here: each
// test builds its dict inline. Only id and depTs matter to the queue.
(:test)
const RQ_NOW = 1718000000;

(:test)
function testReminderIdShape(logger) {
    var id = ReminderQueue.buildId("8507000", 1718000600, "IC1");
    return id.equals("8507000|1718000600|IC1")
        && ReminderQueue.buildId("8507000", 1718000600, null).equals("8507000|1718000600|");
}

(:test)
function testSaveReminderCarriesStableId(logger) {
    var focused = { "dest" => "Brig", "depTs" => 1718000600, "line" => "IR90" };
    var a = PhoneSync.buildSaveReminder(focused, "8507000", "Bern", 46.9489, 7.4396);
    var b = PhoneSync.buildSaveReminder(focused, "8507000", "Bern", 46.9489, 7.4396);
    return a["id"].equals(ReminderQueue.buildId("8507000", 1718000600, "IR90"))
        && a["id"].equals(b["id"]);
}

(:test)
function testReminderEnqueueReplaces(logger) {
    Storage.deleteValue("pendingReminder");
    var a = { "id" => ReminderQueue.buildId("8507000", RQ_NOW + 600, "IC1"), "depTs" => RQ_NOW + 600 };
    var b = { "kind" => "saveReminder", "id" => ReminderQueue.buildId("8501120", RQ_NOW + 900, "IR90"),
        "dest" => "Visp", "depTs" => RQ_NOW + 900 };
    ReminderQueue.enqueue(a, a["id"], RQ_NOW);
    ReminderQueue.enqueue(b, b["id"], RQ_NOW + 10);
    var pending = ReminderQueue.getPending();
    var replaced = pending["id"].equals(b["id"]) && pending["attempts"] == 1;
    Storage.deleteValue("pendingReminder");
    return replaced;
}

(:test)
function testReminderAckMatchClears(logger) {
    Storage.deleteValue("pendingReminder");
    var p = { "id" => ReminderQueue.buildId("8507000", RQ_NOW + 600, "IC1"), "depTs" => RQ_NOW + 600 };
    ReminderQueue.enqueue(p, p["id"], RQ_NOW);
    var matched = ReminderQueue.ack(p["id"]);
    var cleared = !ReminderQueue.hasPending();
    Storage.deleteValue("pendingReminder");
    return matched && cleared;
}

(:test)
function testReminderAckMismatchKeeps(logger) {
    Storage.deleteValue("pendingReminder");
    var p = { "id" => ReminderQueue.buildId("8507000", RQ_NOW + 600, "IC1"), "depTs" => RQ_NOW + 600 };
    ReminderQueue.enqueue(p, p["id"], RQ_NOW);
    var matched = ReminderQueue.ack("someone|else|X");
    var kept = ReminderQueue.hasPending();
    Storage.deleteValue("pendingReminder");
    return !matched && kept && !ReminderQueue.ack(null);
}

(:test)
function testReminderExpiry(logger) {
    var live = { "payload" => { "id" => ReminderQueue.buildId("8507000", RQ_NOW + 600, "IC1"), "depTs" => RQ_NOW + 600 }, "attempts" => 1 };
    var past = { "payload" => { "id" => ReminderQueue.buildId("8507000", RQ_NOW - 200, "IC1"), "depTs" => RQ_NOW - 200 }, "attempts" => 1 };
    var grace = { "payload" => { "id" => ReminderQueue.buildId("8507000", RQ_NOW - 100, "IC1"), "depTs" => RQ_NOW - 100 }, "attempts" => 1 };
    return !ReminderQueue.isExpired(live, RQ_NOW)
        && ReminderQueue.isExpired(past, RQ_NOW)
        && !ReminderQueue.isExpired(grace, RQ_NOW);
}

(:test)
function testReminderDrainPrunesExpired(logger) {
    Storage.deleteValue("pendingReminder");
    ReminderQueue.mLastDrainTs = null;
    var p = { "id" => ReminderQueue.buildId("8507000", RQ_NOW - 600, "IC1"), "depTs" => RQ_NOW - 600 };
    ReminderQueue.enqueue(p, p["id"], RQ_NOW - 700);
    ReminderQueue.drainIfDue(RQ_NOW);
    var pruned = !ReminderQueue.hasPending();
    Storage.deleteValue("pendingReminder");
    return pruned;
}

(:test)
function testReminderDrainCapsAttempts(logger) {
    Storage.deleteValue("pendingReminder");
    ReminderQueue.mLastDrainTs = null;
    var p = { "id" => ReminderQueue.buildId("8507000", RQ_NOW + 600, "IC1"), "depTs" => RQ_NOW + 600 };
    ReminderQueue.enqueue(p, p["id"], RQ_NOW);
    for (var i = 0; i < 10; i++) {
        ReminderQueue.drainIfDue(RQ_NOW + i * 10);
    }
    // 1 initial + 4 drains reaches the cap; the fifth drain deletes instead
    var gone = !ReminderQueue.hasPending();
    Storage.deleteValue("pendingReminder");
    return gone;
}

(:test)
function testReminderDrainThrottled(logger) {
    Storage.deleteValue("pendingReminder");
    ReminderQueue.mLastDrainTs = null;
    var p = { "id" => ReminderQueue.buildId("8507000", RQ_NOW + 600, "IC1"), "depTs" => RQ_NOW + 600 };
    ReminderQueue.enqueue(p, p["id"], RQ_NOW);
    ReminderQueue.drainIfDue(RQ_NOW);
    ReminderQueue.drainIfDue(RQ_NOW + 1);
    ReminderQueue.drainIfDue(RQ_NOW + 2);
    var once = ReminderQueue.getPending()["attempts"] == 2;
    ReminderQueue.drainIfDue(RQ_NOW + 6);
    var twice = ReminderQueue.getPending()["attempts"] == 3;
    Storage.deleteValue("pendingReminder");
    return once && twice;
}

(:test)
function testProtocolVersionTwo(logger) {
    return PhoneSync.PROTOCOL_VERSION == 2;
}
