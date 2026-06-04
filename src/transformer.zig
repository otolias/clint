const std = @import("std");

const Allocator = std.mem.Allocator;
const ArgIteratorGeneral = std.process.ArgIteratorGeneral;
const ArrayList = std.ArrayList;
const Dir = std.fs.Dir;

const CompDBEntry = @import("comp_db.zig").CompDBEntry;

pub const Transformer = struct {
    allocator: Allocator,
    buf_path: []u8,
    buf_token: []u8,
    dir: Dir,
    entry: CompDBEntry,
    started: bool,
    token_list: ArrayList([]const u8),

    pub fn init(allocator: Allocator, entry: CompDBEntry) !@This() {
        const buf_path = try allocator.alloc(u8, std.fs.max_path_bytes);
        errdefer allocator.free(buf_path);

        const buf_token = try allocator.alloc(u8, std.fs.max_path_bytes);
        errdefer allocator.free(buf_token);

        const dir = try std.fs.cwd().openDir(entry.directory, .{});
        errdefer dir.close();

        const token_list = ArrayList([]const u8).init(allocator);
        errdefer token_list.deinit();

        return .{
            .allocator = allocator,
            .buf_path = buf_path,
            .buf_token = buf_token,
            .dir = dir,
            .entry = entry,
            .started = false,
            .token_list = token_list,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.buf_path);
        self.allocator.free(self.buf_token);

        for (self.token_list.items) |item|
            self.allocator.free(item);

        self.token_list.deinit();
        self.dir.close();
    }

    pub fn append(self: *@This(), item: []const u8) !void {
        const duped = try self.allocator.dupe(u8, item);
        try self.token_list.append(duped);
    }

    pub fn parse(self: *@This(), iter: *ArgIteratorGeneral(.{}), token: []const u8) !void {
        // Start parsing when command line flags are encountered
        if (!self.started and std.mem.startsWith(u8, token, "-"))
            self.started = true;

        if (!self.started) {
            try self.append(token);
            return;
        }

        // Replace -I
        if (std.mem.startsWith(u8, token, "-I")) {
            const rel_path = token[2..];
            const abs_path = try self.dir.realpath(rel_path, self.buf_path);

            const written = try std.fmt.bufPrint(self.buf_token, "-I{s}", .{abs_path});
            try self.append(written);
            return;
        }

        // Replace -Isystem
        if (std.mem.startsWith(u8, token, "-isystem")) {
            const rel_path = token[8..];
            const abs_path = try self.dir.realpath(rel_path, self.buf_path);

            const written = try std.fmt.bufPrint(self.buf_token, "-isystem{s}", .{abs_path});
            try self.append(written);
            return;
        }

        // Replace output file
        if (std.mem.startsWith(u8, token, "-o")) {
            _ = iter.next();
            try self.append("-o");
            try self.append("/dev/null");
            return;
        }

        // Skip -MD args
        if (std.mem.startsWith(u8, token, "-MD"))
            return;

        // Skip -MQ and -MF flags and their value
        if (std.mem.startsWith(u8, token, "-MQ") or std.mem.startsWith(u8, token, "-MF")) {
            _ = iter.next();
            return;
        }

        // Ignore other '-' args
        if (std.mem.startsWith(u8, token, "-")) {
            try self.append(token);
            return;
        }

        // Replace input file
        if (std.mem.eql(u8, self.entry.file, token)) {
            const filepath = try self.dir.realpath(self.entry.file, self.buf_path);
            try self.append(filepath);
            return;
        }

        // Try to replace other arguments as paths
        const path = self.dir.realpath(token, self.buf_path) catch {
            try self.append(token);
            return;
        };

        try self.append(path);
    }

    pub fn getArgs(self: *@This()) [][]const u8 {
        return self.token_list.items;
    }
};
