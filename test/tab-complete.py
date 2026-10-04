#!/usr/bin/env python3
"""Completes command lines in a real interactive shell, through a pty, with
clod's completion loaded, and prints each line as the shell completed it.

    test/tab-complete.py bash|zsh LINE...

For each LINE it waits for the shell's prompt, types the line and Tab, then
Ctrl-A and `echo RESULT: `, and Enter: the shell handles keys in order,
completion included, so the echoed line is the completed one. Keys typed before
the prompt would reach the terminal's own line editing instead of the shell's,
so nothing is typed until the prompt shows. The environment (HOME, PATH) is
passed through.
"""
import os
import pty
import select
import sys
import time

shell, lines = sys.argv[1], sys.argv[2:]
prompt = "tab-complete> "
argv = {"bash": ["bash", "--norc", "--noprofile", "-i"], "zsh": ["zsh", "-f", "-i"]}[shell]
env = dict(os.environ, TERM="dumb", PS1=prompt, PROMPT=prompt)

pid, fd = pty.fork()
if pid == 0:
    os.execvpe(argv[0], argv, env)

out = b""


def wait_for(marker, timeout=30):
    """Reads until the output holds marker; returns what came before it."""
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


# zsh picks vi keys when $EDITOR mentions vi, and Ctrl-A needs emacs keys. Its
# compinit asks before using group-writable function directories, as a CI
# runner's are; -u skips that, and the shim then finds compinit already run.
setup = "bindkey -e; autoload -Uz compinit && compinit -u" if shell == "zsh" else "set -o emacs"
wait_for(prompt.encode())
os.write(fd, f'{setup}; eval "$(clod completion)"\n'.encode())
wait_for(prompt.encode())
for line in lines:
    os.write(fd, line.encode() + b"\t\x01echo RESULT: \n")
    # the terminal echoes the typed "echo RESULT: " too, but not after a newline
    wait_for(b"\nRESULT: ")
    print(wait_for(b"\r\n").decode().rstrip())
    wait_for(prompt.encode())
os.write(fd, b"exit\n")
os.waitpid(pid, 0)
