#Requires AutoHotkey v2.0

icons := {
    "left": "←",
    "right": "→",
    "up": "↑",
    "down": "↓",
    "space": "␣",
    "enter": "↵",
    "tab": "⇥",
    "backspace": "⌫",
    "delete": "⌦",
}

Obj2Str(obj) {
    return JSON.stringify(obj, 4)
}

Objs2Str(objs*) {
    result := ""
    for _, obj in objs {
        result .= Obj2Str(obj) . "`n"
    }
    return result
}
