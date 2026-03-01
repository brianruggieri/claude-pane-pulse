#!/usr/bin/env python3
"""PTY wrapper for claude-pane-pulse.

Runs a command in a pseudo-terminal (PTY), writing output to both the
current terminal (stdout) and a named FIFO for background monitoring.

This replaces the macOS `script -F` approach, which consistently fails
with "Permission denied" when called from inside a bash function on
macOS Sonoma due to PTY allocation restrictions in that context.

Usage: pty_wrapper.py <fifo_path> <command> [args...]
"""

import os
import pty
import sys


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: pty_wrapper.py <fifo_path> <command> [args...]",
            file=sys.stderr,
        )
        sys.exit(1)

    pipe_path = sys.argv[1]
    cmd = sys.argv[2:]

    # Open the named pipe for writing.
    # This call blocks until the reading end is also open, which synchronises
    # with the bash monitor background process that opened the FIFO for reading.
    pipe_fd = os.open(pipe_path, os.O_WRONLY)

    def read_and_tee(fd):
        """Read a chunk from the master PTY and mirror it to the monitor FIFO."""
        try:
            data = os.read(fd, 4096)
        except OSError:
            return b""
        if data:
            try:
                os.write(pipe_fd, data)
            except OSError:
                pass  # Monitor process may have exited; ignore FIFO write errors
        return data

    try:
        status = pty.spawn(cmd, read_and_tee)
    finally:
        try:
            os.close(pipe_fd)
        except OSError:
            pass

    # Propagate the child process exit code
    if os.WIFEXITED(status):
        sys.exit(os.WEXITSTATUS(status))
    elif os.WIFSIGNALED(status):
        sys.exit(128 + os.WTERMSIG(status))


if __name__ == "__main__":
    main()
