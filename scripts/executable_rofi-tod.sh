#!/usr/bin/env bash
set -e

TODO=$(rofi -dmenu -l 0 -yoffset -300 -p "todo" -theme-str 'entry { placeholder: "what do you need todo?"; } inputbar { children: [prompt, textbox-prompt-colon, entry];}')

if [[ -n $TODO ]]; then
    tod t q -c "$TODO"
    notify-send -a Todoist "saved todo: $TODO"
fi
