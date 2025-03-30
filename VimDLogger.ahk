#Requires AutoHotkey v2.0
#Include <Aris\hoppfrosch\log4ahk@157f558\log4ahk>

class VimDLogger extends Logger {
    dump(obj*) {
        for key, value in obj {
            this.info(key " = " value)
        }
    }
}
