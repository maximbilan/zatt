const std = @import("std");
const smc = @import("smc.zig");
const c = smc.c;

pub const Error = smc.Error || error{
    BatteryNotFound,
    InvalidCapacity,
    OutputFailed,
    PowerSourceUnavailable,
};

const PowerSourceInfo = struct {
    percent: u8,
    is_charging: bool,
    plugged_in: bool,
    cycles: ?u32,
    health: [64]u8 = [_]u8{0} ** 64,
    health_len: usize = 0,
};

pub fn disable() smc.Error!void {
    var session = try smc.Session.open();
    defer session.close();
    try writeChargingInhibit(&session, true);
}

pub fn enable() smc.Error!void {
    var session = try smc.Session.open();
    defer session.close();
    try writeChargingInhibit(&session, false);
}

pub fn setLimit(limit: u8) smc.Error!void {
    var session = try smc.Session.open();
    defer session.close();
    try writeChargeLimit(&session, limit);
}

pub fn resetLimit() smc.Error!void {
    try setLimit(100);
}

pub fn status() Error!void {
    var session = try smc.Session.open();
    defer session.close();

    const charging_inhibit = try readChargingInhibit(&session);
    const limit = readChargeLimit(&session) catch |err| switch (err) {
        error.KeyNotFound => 100,
        else => return err,
    };
    const info = try readPowerSourceInfo();

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();

    writer.writeAll("══════════════════════════════\n") catch unreachable;
    writer.writeAll("  Battery Status\n") catch unreachable;
    writer.writeAll("══════════════════════════════\n") catch unreachable;

    const filled = @min(@as(usize, 10), (@as(usize, info.percent) + 5) / 10);
    writer.writeAll("  Charge:       ") catch unreachable;
    for (0..10) |index| {
        writer.writeAll(if (index < filled) "█" else "░") catch unreachable;
    }
    writer.print(" {d}%\n", .{info.percent}) catch unreachable;

    const charging_label = if (charging_inhibit)
        "disabled (inhibited)"
    else if (info.is_charging)
        "charging"
    else
        "not charging";
    writer.print("  Charging:     {s}\n", .{charging_label}) catch unreachable;
    writer.print("  Plugged in:   {s}\n", .{if (info.plugged_in) "yes" else "no"}) catch unreachable;
    writer.print("  Health:       {s}\n", .{healthSlice(&info)}) catch unreachable;

    if (info.cycles) |cycles| {
        writer.print("  Cycles:       {d}\n", .{cycles}) catch unreachable;
    } else {
        writer.writeAll("  Cycles:       Unknown\n") catch unreachable;
    }

    if (limit == 100) {
        writer.writeAll("  Limit:        none\n") catch unreachable;
    } else {
        writer.print("  Limit:        {d}%\n", .{limit}) catch unreachable;
    }

    writer.writeAll("══════════════════════════════\n") catch unreachable;
    std.fs.File.stdout().writeAll(stream.getWritten()) catch return error.OutputFailed;
}

fn readPowerSourceInfo() Error!PowerSourceInfo {
    const snapshot = c.IOPSCopyPowerSourcesInfo();
    if (snapshot == null) return error.PowerSourceUnavailable;
    defer c.CFRelease(snapshot);

    const sources = c.IOPSCopyPowerSourcesList(snapshot);
    if (sources == null) return error.PowerSourceUnavailable;
    defer c.CFRelease(sources);

    if (c.CFArrayGetCount(sources) == 0) return error.BatteryNotFound;

    const source = c.CFArrayGetValueAtIndex(sources, 0);
    const description = c.IOPSGetPowerSourceDescription(snapshot, source);
    if (description == null) return error.PowerSourceUnavailable;

    const current_capacity = dictGetInt(description, "Current Capacity") orelse return error.InvalidCapacity;
    const max_capacity = dictGetInt(description, "Max Capacity") orelse return error.InvalidCapacity;
    if (current_capacity < 0 or max_capacity <= 0) return error.InvalidCapacity;

    var info = PowerSourceInfo{
        .percent = percentage(current_capacity, max_capacity),
        .is_charging = dictGetBool(description, "Is Charging") orelse false,
        .plugged_in = false,
        .cycles = null,
    };

    if (dictGetString(description, "Power Source State", &info.health)) |state| {
        info.plugged_in = std.mem.eql(u8, state, "AC Power");
    }

    if (dictGetString(description, "BatteryHealth", &info.health)) |health| {
        info.health_len = health.len;
    } else {
        std.mem.copyForwards(u8, info.health[0.."Unknown".len], "Unknown");
        info.health_len = "Unknown".len;
    }

    if (dictGetInt(description, "Cycle Count") orelse readBatteryRegistryInt("CycleCount")) |cycles| {
        if (cycles >= 0) {
            info.cycles = @intCast(cycles);
        }
    }

    return info;
}

fn healthSlice(info: *const PowerSourceInfo) []const u8 {
    return info.health[0..info.health_len];
}

fn percentage(current_capacity: i64, max_capacity: i64) u8 {
    const numerator = current_capacity * 100 + @divTrunc(max_capacity, 2);
    const rounded = @min(@as(i64, 100), @divTrunc(numerator, max_capacity));
    return @intCast(rounded);
}

fn readChargingInhibit(session: *smc.Session) smc.Error!bool {
    const value = session.readU8("CH0B") catch |err| switch (err) {
        error.KeyNotFound => return readChargingInhibitFallback(session),
        else => return err,
    };
    return value != 0;
}

fn readChargingInhibitFallback(session: *smc.Session) smc.Error!bool {
    return session.readU8("CH0C") catch |err| switch (err) {
        error.KeyNotFound => {
            const value = try session.read("CHTE");
            return value.bytes[0] != 0;
        },
        else => return err,
    } != 0;
}

fn writeChargingInhibit(session: *smc.Session, disabled: bool) smc.Error!void {
    session.writeU8("CH0B", if (disabled) 1 else 0) catch |err| switch (err) {
        error.KeyNotFound => return writeChargingInhibitFallback(session, disabled),
        else => return err,
    };
}

fn writeChargingInhibitFallback(session: *smc.Session, disabled: bool) smc.Error!void {
    const tahoe_bytes = if (disabled)
        [_]u8{ 1, 0, 0, 0 }
    else
        [_]u8{ 0, 0, 0, 0 };

    session.write("CHTE", &tahoe_bytes) catch |err| switch (err) {
        error.KeyNotFound => try session.writeU8("CH0C", if (disabled) 2 else 0),
        else => return err,
    };
}

fn readChargeLimit(session: *smc.Session) smc.Error!u8 {
    return session.readU8("BCLM") catch |err| switch (err) {
        error.KeyNotFound => {
            const raw = try session.readU8("CHWA");
            return if (raw == 1) 80 else 100;
        },
        else => return err,
    };
}

fn writeChargeLimit(session: *smc.Session, limit: u8) smc.Error!void {
    session.writeU8("BCLM", limit) catch |err| switch (err) {
        error.KeyNotFound => {
            const fallback_value: u8 = switch (limit) {
                80 => 1,
                100 => 0,
                else => return error.KeyNotFound,
            };
            try session.writeU8("CHWA", fallback_value);
        },
        else => return err,
    };
}

fn dictGetInt(dict: c.CFDictionaryRef, key_name: [*:0]const u8) ?i64 {
    const value = dictGetValue(dict, key_name) orelse return null;
    var result: i64 = 0;
    const number: c.CFNumberRef = @ptrCast(@alignCast(value));
    if (c.CFNumberGetValue(number, c.kCFNumberSInt64Type, &result) == 0) return null;
    return result;
}

fn dictGetBool(dict: c.CFDictionaryRef, key_name: [*:0]const u8) ?bool {
    const value = dictGetValue(dict, key_name) orelse return null;
    const boolean: c.CFBooleanRef = @ptrCast(@alignCast(value));
    return c.CFBooleanGetValue(boolean) != 0;
}

fn dictGetString(dict: c.CFDictionaryRef, key_name: [*:0]const u8, buffer: []u8) ?[]const u8 {
    const value = dictGetValue(dict, key_name) orelse return null;
    const string: c.CFStringRef = @ptrCast(@alignCast(value));
    if (buffer.len == 0) return null;
    if (c.CFStringGetCString(string, buffer.ptr, @intCast(buffer.len), c.kCFStringEncodingUTF8) == 0) return null;
    return std.mem.sliceTo(buffer, 0);
}

fn dictGetValue(dict: c.CFDictionaryRef, key_name: [*:0]const u8) ?*const anyopaque {
    const key = c.CFStringCreateWithCString(c.kCFAllocatorDefault, key_name, c.kCFStringEncodingUTF8);
    if (key == null) return null;
    defer c.CFRelease(key);

    return c.CFDictionaryGetValue(dict, key);
}

fn readBatteryRegistryInt(property_name: [*:0]const u8) ?i64 {
    const matching = c.IOServiceMatching("AppleSmartBattery") orelse return null;
    const service = c.IOServiceGetMatchingService(c.kIOMainPortDefault, matching);
    if (service == 0) return null;
    defer _ = c.IOObjectRelease(service);

    const key = c.CFStringCreateWithCString(c.kCFAllocatorDefault, property_name, c.kCFStringEncodingUTF8);
    if (key == null) return null;
    defer c.CFRelease(key);

    const value = c.IORegistryEntryCreateCFProperty(service, key, c.kCFAllocatorDefault, 0);
    if (value == null) return null;
    defer c.CFRelease(value);

    if (c.CFGetTypeID(value) != c.CFNumberGetTypeID()) return null;

    var result: i64 = 0;
    const number: c.CFNumberRef = @ptrCast(@alignCast(value));
    if (c.CFNumberGetValue(number, c.kCFNumberSInt64Type, &result) == 0) return null;
    return result;
}
