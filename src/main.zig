//
// Copyright (C) 2026 otolias
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

const std = @import("std");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const RealPathError = std.posix.RealPathError;

const CompDB = @import("comp_db.zig").CompDB;
const CompDBError = @import("comp_db.zig").CompDBError;
const Transformer = @import("transformer.zig").Transformer;

fn lintFile(allocator: std.mem.Allocator, comp_db: CompDB, filename: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    const abs_name = try std.fs.realpathAlloc(allocator, filename);
    defer allocator.free(abs_name);

    const entry = try comp_db.findFile(abs_name);

    var transformer = try Transformer.init(allocator, entry);
    defer transformer.deinit();

    var iter = try std.process.ArgIteratorGeneral(.{}).init(allocator, entry.command);
    defer iter.deinit();

    while (iter.next()) |token|
        try transformer.parse(&iter, token);

    try transformer.append("-fno-diagnostics-color");

    // Run command
    var child = std.process.Child.init(transformer.getArgs(), allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stderr_reader = child.stderr.?.reader();
    var stderr_buf: [1024]u8 = undefined;

    while (try stderr_reader.readUntilDelimiterOrEof(&stderr_buf, '\n')) |line| {
        _ = try stdout.print("{s}\n", .{line});
    }

    _ = try child.wait();
}

pub fn main() !void {
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Locate compilation database
    var comp_db = CompDB.init(allocator) catch |err| switch (err) {
        File.OpenError.FileNotFound => {
            try stderr.print("Error: compile_commands.json was not found\n", .{});
            return;
        },
        else => {
            return err;
        },
    };
    defer comp_db.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    while (args.next()) |file| {
        lintFile(allocator, comp_db, file) catch |err| switch (err) {
            RealPathError.FileNotFound => {
                try stderr.print("Error: File {s} was not found\n", .{file});
            },
            CompDBError.FileNotInCompDB => {
                try stderr.print("Error: File {s} was not found in compile_commands.json\n", .{file});
            },
            else => {
                try stderr.print("{}\n", .{err});
            },
        };
    }
}
