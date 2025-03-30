#Requires AutoHotkey v2.0

/** @type {VimDWin} */
win := vimd.initWin("vscode", "ahk_exe code.exe")
win.keyToMode1 := "F1"
win.keyToMode0 := "F2"
/** @type {VimDMode} */
mode1 := win.initMode(1, , "normal", 3)
mode1.MapKey("e e", ObjBindMethod(VimD.logger, "info", "typed e e"), "msgbox")
mode1.onBeforeKey := ObjBindMethod(mode1, "BeforeKey")