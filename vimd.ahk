class VimD {
    static arrModeName := ["None", "Vim"
    ]
    ;static charSplit := "※" ;分隔各命令
    /** @type {VimDWin} */
    static curWin := {} ;记录当前的窗口，用来出错后 init
    static tipLevel := 15
    static tipLevel1 := 16 ;其他辅助显示

    /** @type {Logger} */
    static logger := Logger()
    /** @type {Map<String, VimDWin>} */
    static wins := Map() ;在 initWin里设置

    static __New() {
        SetTitleMatchMode('Fast')
        ; VimD.logger.debug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
        ; this.logger.is_use_editor := true
        ; this.logger.level := this.logger.level_trace
        VimD.logger.setLogLevel(LogLevel.DEBUG)
        ;HotIfWinActive ;TODO 关闭
    }

    ;NOTE 核心，由各插件自行调用
    /**
     * 
     * @param winName 
     * @param winTitle 
     * @returns {VimDWin}
     */
    static InitWin(winName, winTitle) {
        ;msgbox(winName . "`n" . json.stringify(this.wins, 4))
        if !this.wins.has(winName)
            this.wins[winName] := VimDWin(winName)
        /** @type {VimDWin} */
        win := this.wins[winName]
        win.winTitle := winTitle
        return win
    }

    ;NOTE 运行出错后必须要执行此方法，否则下次 VimD 的第一个键会无效
    static ErrorHandler(msg := "") {
        if (IsObject(this.curWin))
            this.curWin.curMode.init()
        if (msg != "") {
            msgbox(A_ThisFunc . "`n" . msg, , 0x40000)
            exit
        }
    }

    ;VimDMode.ShowTips
    static HideTips() {
        tooltip(, , , VimD.tipLevel)
    }

    static HideTips1() => tooltip(, , , VimD.tipLevel1)
    static ShowTips1(str, x := 0, y := 0) => tooltip(str, x, y, VimD.tipLevel1) ;辅助显示，固定在某区域

    ; static checkInclude() {
    ;     SplitPath(A_LineFile, , &dir)
    ;     fp := format("{1}\VimDInclude.ahk", dir)
    ;     str := fileread(fp)
    ;     arr := StrSplit(rtrim(fileread(fp), "`r`n"), "`n", "`r").map(v => StrSplit(v, "\")[2])
    ;     ;objInclude := StrSplit(rtrim(fileread(fp),"`r`n"), "`n", "`r").map(v=>)
    ;     if (hyf_checkNewPlugin(A_WorkingDir "\VimDInclude.ahk", [[A_WorkingDir, "wins"
    ;     ]], "VimD_")) {
    ;         f := FileOpen(fp, "w", "utf-8-raw")
    ;         strInclude := ""
    ;         loop files, format("{1}\wins\*", A_LineFile.dir()), "D"
    ;             strInclude .= format("#include wins\{1}\VimD_{1}.ahk`n", A_LoopFileName)
    ;         f.write(strInclude)
    ;         f.close()
    ;     }
    ; }

}

; OnError(ErrorHandler)
; ErrorHandler(exception, mode) {
;     msgbox(exception.file . "`n" . exception.line, , 0x40000)
;     VimD.ErrorHandler() ;NOTE 否则 VimD 下个按键会无效
; }

#include VimDInclude.ahk
#include VimDWin.ahk
#include VimDMode.ahk