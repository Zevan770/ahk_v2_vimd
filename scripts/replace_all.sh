#!/bin/bash

function replace_all() {
    local OLD_TEXT="$1"
    local NEW_TEXT="$2"

    if [[ -z "$OLD_TEXT" || -z "$NEW_TEXT" ]]; then
        echo "Usage: replace_all <old_text> <new_text>"
        return 1
    fi

    rg -iw --glob "*.ahk" --no-ignore "$OLD_TEXT" --files-with-matches | \
    xargs -I{} sh -c "rg -iw --passthru --replace \"$NEW_TEXT\" \"$OLD_TEXT\" {} | sponge {}"
}

# Iterate through regexs.json and perform replacements
jq -c '.[]' scripts/regexs.json | while read -r pair; do
    FROM=$(echo "$pair" | jq -r '.from')
    TO=$(echo "$pair" | jq -r '.to')
    replace_all "$FROM" "$TO"
done
