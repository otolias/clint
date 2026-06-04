Clint
-----------

The C lint(er): Extract compiler diagnostics from any compiler with flags extracted from a
compilation database.

## Installation

Note: Only tested in Linux.

### From Release

Get the latest release from [Releases](https://github.com/otolias/clint/releases), download
executable, change permissions to execute and install somewhere in ```$PATH```
(e.g. ```/usr/local/bin```).

### From Source

Install [Zig](https://ziglang.org/) version 0.13.

```sh
zig build -Doptimize=ReleaseSafe
cp zig-out/bin/clint /usr/local/bin/
```

## Usage

You need a ```compile_commands.json``` in the project root. CMake and Meson create one in the build
directory, so you can symlink it to the project root. If using Make, you can use
[Bear](https://github.com/rizsotto/Bear). Then, running:

```sh
clint <file_1>.c <file_2>.c
```

transforms and executes the compilation command, and then outputs the compiler diagnostics.

## Transformation

- Replaces -I and -isystem relative paths with absolute.
- Replaces all relative paths with absolute (including the input file), if possible.
- Replaces -o output with /dev/null
- Removes -M, -MF and -MQ dependency generation flags

All other arguments are left as-is.

## Acknowledges

Inspired by [gccdiag](https://gitlab.com/andrejr/gccdiag).
