#!/usr/bin/env python3
"""PTY wrapper for claude-pane-pulse.

Runs a command in a pseudo-terminal (PTY), writing output to both the
current terminal (stdout) and a named FIFO for background monitoring.

Key improvements over pty.spawn():
  - Reads the real terminal size (TIOCGWINSZ) and sets it on the child PTY
    before exec, so Claude Code's TUI renders at the correct width.
  - Installs a SIGWINCH handler that propagates every terminal resize to the
    child PTY, so split-pane resizes, window drags, and tmux pane adjustments
    are all reflected immediately inside the Claude Code TUI.

Usage: pty_wrapper.py <fifo_path> <command> [args...]
"""

import ctypes
import ctypes.util
import fcntl
import os
import select
import signal
import struct
import sys
import termios
import tty


def _rename_process(name: str) -> None:
    """Rename this process so terminals/ps show 'name' instead of 'Python'.

    Uses setprogname() on macOS/BSD, prctl(PR_SET_NAME) on Linux.
    Silently ignored on failure — purely cosmetic.
    """
    try:
        libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
        bname = name.encode()
        if hasattr(libc, "setprogname"):
            libc.setprogname(bname)          # macOS / BSD
        elif hasattr(libc, "prctl"):
            libc.prctl(15, bname, 0, 0, 0)  # Linux PR_SET_NAME
    except Exception:
        pass


def _get_terminal_size():
    """Return (rows, cols) of the controlling terminal, or (24, 80) fallback."""
    try:
        buf = struct.pack("HHHH", 0, 0, 0, 0)
        buf = fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, buf)
        rows, cols, _, _ = struct.unpack("HHHH", buf)
        if rows > 0 and cols > 0:
            return rows, cols
    except (OSError, struct.error):
        pass
    return 24, 80


def _set_pty_size(fd, rows, cols):
    """Set the window size on a PTY file descriptor (best-effort)."""
    try:
        buf = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, buf)
    except OSError:
        pass


def main():
    # Rename the process so iTerm2/ps shows "ccp" instead of "Python"
    _rename_process("ccp")

    if len(sys.argv) < 3:
        print(
            "Usage: pty_wrapper.py <fifo_path> <command> [args...]",
            file=sys.stderr,
        )
        sys.exit(1)

    pipe_path = sys.argv[1]
    cmd = sys.argv[2:]

    # Open the FIFO for writing.  Blocks until the monitor's read end is open,
    # synchronising startup with the bash background process.
    pipe_fd = os.open(pipe_path, os.O_WRONLY)

    # Capture terminal dimensions before forking so the child starts at the
    # right size rather than the PTY default (typically 24×80).
    rows, cols = _get_terminal_size()

    # Fork with a new PTY allocated on the child side.
    child_pid, master_fd = os.forkpty()

    if child_pid == 0:
        # ── Child process ────────────────────────────────────────────────────
        # Resize the slave PTY to match the real terminal before exec.
        _set_pty_size(sys.stdout.fileno(), rows, cols)
        try:
            os.execvp(cmd[0], cmd)
        except OSError as exc:
            print(f"exec failed: {exc}", file=sys.stderr)
        os._exit(127)

    # ── Parent process ───────────────────────────────────────────────────────

    # Also size the master side (belt-and-suspenders: some implementations
    # only honour the ioctl on whichever side you call it first).
    _set_pty_size(master_fd, rows, cols)

    # Forward every SIGWINCH (terminal resize) to the child's PTY.  This
    # covers pane splits in tmux/iTerm2, window drags, font-size changes, etc.
    def _on_sigwinch(signum, frame):  # noqa: ARG001
        new_rows, new_cols = _get_terminal_size()
        _set_pty_size(master_fd, new_rows, new_cols)
        try:
            os.kill(child_pid, signal.SIGWINCH)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGWINCH, _on_sigwinch)

    # Put stdin into raw mode so every keypress is forwarded byte-for-byte to
    # the child PTY without line-buffering or echo from our side.
    stdin_fd = sys.stdin.fileno()
    saved_tc = None
    try:
        saved_tc = termios.tcgetattr(stdin_fd)
        tty.setraw(stdin_fd, termios.TCSANOW)
    except termios.error:
        pass  # stdin is not a tty (e.g., redirected in tests)

    stdout_fd = sys.stdout.fileno()
    eof = False

    try:
        while not eof:
            try:
                rfds, _, _ = select.select([master_fd, stdin_fd], [], [], 0.5)
            except (select.error, InterruptedError):
                # EINTR from SIGWINCH or other signal — retry immediately
                continue

            for fd in rfds:
                if fd == master_fd:
                    try:
                        data = os.read(master_fd, 4096)
                    except OSError:
                        data = b""
                    if not data:
                        # EOF: slave side closed (child exited)
                        eof = True
                        break
                    # Display to user's terminal
                    try:
                        os.write(stdout_fd, data)
                    except OSError:
                        pass
                    # Tee to FIFO for the title monitor
                    try:
                        os.write(pipe_fd, data)
                    except OSError:
                        pass  # Monitor may have exited; ignore

                elif fd == stdin_fd:
                    try:
                        data = os.read(stdin_fd, 4096)
                    except OSError:
                        data = b""
                    if data:
                        try:
                            os.write(master_fd, data)
                        except OSError:
                            pass

    finally:
        # Restore terminal state before we exit
        if saved_tc is not None:
            try:
                termios.tcsetattr(stdin_fd, termios.TCSAFLUSH, saved_tc)
            except termios.error:
                pass
        # Close FIFO so the monitor sees EOF and exits cleanly
        try:
            os.close(pipe_fd)
        except OSError:
            pass
        try:
            os.close(master_fd)
        except OSError:
            pass

    # Reap the child and propagate its exit code
    _, wstatus = os.waitpid(child_pid, 0)
    if os.WIFEXITED(wstatus):
        sys.exit(os.WEXITSTATUS(wstatus))
    elif os.WIFSIGNALED(wstatus):
        sys.exit(128 + os.WTERMSIG(wstatus))


if __name__ == "__main__":
    main()
