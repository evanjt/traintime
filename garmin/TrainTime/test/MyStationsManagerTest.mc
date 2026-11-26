using Toybox.Test;
using Toybox.Application.Storage;

// Unit tests for the pinned "My stations" logic. Built only with `monkeyc -t`
// and excluded from shipping builds. Run headlessly in CI's connectiq-tester.

(:test)
function testReorderNoPins(logger) {
    Storage.deleteValue("myStations");
    var stations = [ { "id" => "near" }, { "id" => "big" }, { "id" => "far" } ];
    var out = MyStationsManager.reorderStations(stations);
    return out[0]["id"].equals("near") && out[1]["id"].equals("big") && out[2]["id"].equals("far");
}

(:test)
function testReorderBubblesPinned(logger) {
    Storage.setValue("myStations", [ { "id" => "big", "name" => "Big", "lat" => null, "lon" => null } ]);
    var stations = [ { "id" => "near" }, { "id" => "big" }, { "id" => "far" } ];
    var out = MyStationsManager.reorderStations(stations);
    Storage.deleteValue("myStations");
    return out[0]["id"].equals("big") && out[1]["id"].equals("near") && out[2]["id"].equals("far");
}

(:test)
function testReorderIgnoresAbsentPin(logger) {
    Storage.setValue("myStations", [ { "id" => "zurich" } ]);
    var stations = [ { "id" => "near" }, { "id" => "big" } ];
    var out = MyStationsManager.reorderStations(stations);
    Storage.deleteValue("myStations");
    return out[0]["id"].equals("near") && out[1]["id"].equals("big");
}

(:test)
function testPinToggle(logger) {
    Storage.deleteValue("myStations");
    MyStationsManager.toggle("8500074", "Sion", 46.23, 7.36);
    var added = MyStationsManager.isPinned("8500074");
    MyStationsManager.toggle("8500074", "Sion", 46.23, 7.36);
    var removed = !MyStationsManager.isPinned("8500074");
    Storage.deleteValue("myStations");
    return added && removed;
}
