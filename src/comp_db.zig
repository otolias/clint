const std = @import("std");

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

pub const CompDBEntry = struct {
    directory: []u8,
    command: []u8,
    file: []u8,
    output: []u8,
};

pub const CompDBError = error{
    FileNotInCompDB,
};

/// Compilation database parser
pub const CompDB = struct {
    arena: ArenaAllocator,
    allocator: Allocator,
    entries: []CompDBEntry,

    /// Search for compilation database in current and parent folders, open
    /// and return file handle.
    fn locateCompDB(allocator: Allocator) !File {
        var par_buf: []u8 = try allocator.alloc(u8, std.fs.max_path_bytes);
        var cur_buf: []u8 = try allocator.alloc(u8, std.fs.max_path_bytes);
        var cwd = try std.fs.cwd().openDir(".", .{});
        defer {
            allocator.free(par_buf);
            allocator.free(cur_buf);
            cwd.close();
        }

        var cur_path = try cwd.realpath(".", cur_buf);
        var file: ?File = null;

        while (true) {
            const file_err = cwd.openFile("compile_commands.json", .{ .mode = .read_only });
            file = file_err catch |err| switch (err) {
                File.OpenError.FileNotFound => {
                    const par_path = try cwd.realpath("..", par_buf);

                    if (std.mem.eql(u8, par_path, cur_path)) {
                        // Reached root directory
                        return err;
                    }

                    // Replace cwd with parent directory
                    const parent = try cwd.openDir("..", .{});

                    // Swap buffers
                    const tmp_buf = par_buf;
                    par_buf = cur_buf;
                    cur_buf = tmp_buf;

                    cwd.close();
                    cwd = parent;
                    cur_path = par_path;

                    continue;
                },
                else => {
                    return err;
                },
            };

            return file.?;
        }
    }

    /// Initialise CompDB parser.
    pub fn init(allocator: Allocator) !@This() {
        const file = try locateCompDB(allocator);
        defer file.close();

        const contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(contents);

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const entries = try std.json.parseFromSliceLeaky([]CompDBEntry, arena.allocator(), contents, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });

        return .{
            .arena = arena,
            .allocator = allocator,
            .entries = entries,
        };
    }

    /// De-allocate resources
    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    /// Find absolute _path_ in compilation database
    pub fn findFile(self: *const @This(), path: []const u8) !CompDBEntry {
        const buf: []u8 = try self.allocator.alloc(u8, std.fs.max_path_bytes);
        defer self.allocator.free(buf);

        for (self.entries) |entry| {
            var directory = try std.fs.cwd().openDir(entry.directory, .{});
            const entry_path = try directory.realpath(entry.file, buf);

            if (std.mem.eql(u8, path, entry_path)) {
                directory.close();
                return entry;
            }

            directory.close();
        }

        return CompDBError.FileNotInCompDB;
    }
};
