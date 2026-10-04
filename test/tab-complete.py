#!/usr/bin/env python3
"""Completes command lines in a real interactive shell, through a pty, with
clod's completion loaded, and prints each line as the shell completed it.

    test/tab-complete.py bash|zsh LINE...

For each LINE it types the line and Tab, then Ctrl-A and `echo RESULT: `, and
Enter: the shell handles keys in order, completion included, so the echoed line
is the completed one. The environment (HOME, PATH) is passed through.
"""
import os
import pty
import select
import sys
import time

shell, lines = sys.argv[1], sys.argv[2:]
argv = {"bash": ["bash", "--norc", "--noprofile", "-i"], "zsh": ["zsh", "-f", "-i"]}[shell]
env = dict(os.environ, TERM="dumb", PS1="$ ", PROMPT="$ ")

pid, fd = pty.fork()
if pid == 0:
    os.execvpe(argv[0], argv, env)

out = b""


def wait_for(marker, timeout=20):
    """Reads until the output holds marker after the last read position."""
    global out
    end = time.time() + timeout
    while marker not in out:
        if time.time() > end:
            sys.exit(f"tab-complete: {shell} timed out; output so far: {out[-500:]!r}")
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            out += os.read(fd, 65536)
    head, _, out = out.partition(marker)
    return head


# zsh picks vi keys when $EDITOR mentions vi, and Ctrl-A needs emacs keys.
emacs = b"bindkey -e; " if shell == "zsh" else b"set -o emacs; "
os.write(fd, emacs + b'eval "$(clod completion)"; echo READY\n')
wait_for(b"READY\r\n")
for line in lines:
    os.write(fd, line.encode() + b"\t\x01echo RESULT: \n")
    # the terminal echoes the typed "echo RESULT: " too, but not after a newline
    wait_for(b"\nRESULT: ")
    print(wait_for(b"\r\n").decode().rstrip())
os.write(fd, b"exit\n")
os.waitpid(pid, 0)
