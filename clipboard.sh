#!/bin/sh
# xclip and wl-paste for Claude Code's Ctrl+V image paste. The container has no
# display, so with clod --clipboard these fetch the image on the host's clipboard
# from the server clod runs there, at $CLOD_CLIPBOARD_URL. Only images are
# read; text requests and copies fail, as with an empty clipboard. Without the
# URL, an installed xclip or wl-paste runs instead.
#
# Claude Code lists the clipboard's types (xclip -t TARGETS -o or wl-paste -l)
# and then reads the image, so the list fetches it and the read, coming right
# after, serves that copy.

name=${0##*/}
if [ -z "${CLOD_CLIPBOARD_URL:-}" ]; then
    [ -x "/usr/bin/$name" ] && exec "/usr/bin/$name" "$@"
    exit 1
fi
cache=${TMPDIR:-/tmp}/clod-clipboard.png

fetch() {
    tmp=$cache.$$
    code=$(curl -sS --max-time 10 -o "$tmp" -w '%{http_code}' "$CLOD_CLIPBOARD_URL" 2>/dev/null)
    if [ "$code" = 200 ] && [ -s "$tmp" ]; then
        mv -f "$tmp" "$cache"
    else
        rm -f "$tmp" "$cache"
        return 1
    fi
}

# The image fetched by the list, if within the last 10 seconds, else a fresh one.
image() {
    if [ -s "$cache" ] && [ $(($(date +%s) - $(stat -c %Y "$cache"))) -le 10 ]; then
        cat "$cache"
    else
        fetch && cat "$cache"
    fi
}

args=" $* "
case $name in
    xclip)
        case $args in *" -o "*|*" -out "*) ;; *) exit 1 ;; esac
        case $args in
            *" TARGETS "*) fetch && printf 'TARGETS\nimage/png\n' ;;
            *" image/png "*) image ;;
            *) exit 1 ;;
        esac
        ;;
    wl-paste)
        case $args in
            *" -l "*|*" --list-types "*) fetch && echo image/png ;;
            *" image/png "*|*" --type=image/png "*) image ;;
            *) exit 1 ;;
        esac
        ;;
    *)
        echo "clod clipboard: run as xclip or wl-paste, not $name" >&2
        exit 1
        ;;
esac
