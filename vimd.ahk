;说明：
;内置两个模式 mode0(原生) 和 mode1(VimD功能)，名称定义在 arrModeName
;默认按键 map 见 MapDefault
;按 ` 从 mode1→mode0
;按 escape 从 mode0→mode1(可能需要优先执行原生的escape功能,见 funCheckEscape)
;按键格式切换
;   keyIn 里，keyMap := VimD.Hot2Map(ThisHotkey) 主要逻辑都用 keyMap 处理
;进阶：
;   全局热键，建议 InitWin 用 ahk_exe，再直接用 hotkey 定义热键
;   支持子窗口管理：各子窗口相对独立，但能在 InitWin 后指定数组[hotwin1, hotwin2]，表明和其共用热键
;   像TC里，比如按了d后，是不希望执行VimD功能的
;   在Cmder里，git界面不想显示其他命令，在cmd界面，想显示git命令
;插件配制：见 wins\Notepad\VimD_Notepad.ahk
;NOTE 注意有两个阶段
;   1. 【定义】热键: MapKey mapDynamic
;   2. 【触发】热键: keyIn 进行各种获取和判断
;NOTE 脚本出错后务必运行 VimD.ErrorHandler()，取消注释末尾的 OnError
;不能简单区分模式的软件，推荐用Fx功能键，设计思路：
;   1. F10 VimD内置调试的功能
;   2. F12 当前软件全局配置，调试等功能
;   3. F1 进入各页面相关功能
;   4. F3 全局功能
;   5. F4 当前页面的动态功能
;   6. F6 根据markdown笔记的提示功能
;   7. F7 脚本的相关提示功能(更强大灵活)
;NOTE by 火冷 <2023-04-15 12:40:54> 重构了动态命令，全整合到 leaderKey2ActionMap 里，用 normal和dynamic区分
;如果第1个键下的命令太多，全显示会太杂乱，增加分组功能，关键词是 group
;   按第1个键，如果有 group 属性则考虑：只出现2级的功能列表(相当于菜单文件夹，而非最终命令)
;   再按第2个键，如果类似菜单文件夹，则显示对应文件夹下的命令
;       NOTE 同时支持按下0时，如果没有匹配到命令，则执行当前显示的所有命令(批量执行分组的所有功能)
;       如果非分组热键，则全局搜索由 groupKeymap 定义的子节点热键
;NOTE 运行中如果某个键的功能无效，其他功能可以，可能是那个功能有问题，一直没执行完

;定义示例
/*
mapF11("{F11}")
mapF11(k0) {
    this.mode1.DefineGroup(k0) ;额外增加这句
    ;推荐简化版
    a := [
        ["分组a","a"],
        [
            ["注释axy","xy"],
            ["注释ayx","yx"],
        ]
    ]
    this.mode1.MapGroup(format("<super>{1}",k0), a)
    ;原始
    this.mode1.MapKey(format("<super>{1}{2}",k0,"b"),,"分组b", 1)
    this.mode1.MapKey(format("<super>{1}{2}",k0,"bxy"),msgbox.bind("bxy"),"注释bxy", 2)
    this.mode1.MapKey(format("<super>{1}{2}",k0,"bxz"),msgbox.bind("bxz"),"注释bxz", 2)
    this.mode1.MapKey(format("<super>{1}{2}",k0,"byx"),msgbox.bind("byx"),"注释byx", 2)
    this.mode1.MapKey(format("<super>{1}{2}",k0,"bz"),msgbox.bind("bz"),"注释bz", 2)
}
*/

class VimD {
    static arrModeName := ["None", "Vim"
    ]
    ;static charSplit := "※" ;分隔各命令
    static winCurrent := 0 ;记录当前的窗口，用来出错后 init
    static tipLevel := 15
    static tipLevel1 := 16 ;其他辅助显示
    static debugLevel := 0 ;用于方便地显示提示信息
    static logger := Logger.getInstance()
    static groupKeymap := "groupString" ;分组的全局搜索时，action 的字段定义在 groupKeymap
    static groupStatus := false
    static groupKeyAll := "{F12}" ;NOTE 执行当前全部命令
    /** @type {Map<String, VimDWin>} */
    static wins := Map() ;在 initWin里设置

    static __new() {
        OutputDebug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
        ;HotIfWinActive ;TODO 关闭
    }

    ;NOTE 核心，由各插件自行调用
    static InitWin(winName, winTitle, cls := unset) {
        ;msgbox(winName . "`n" . json.stringify(this.wins, 4))
        if !this.wins.has(winName)
            this.wins[winName] := VimDWin(winName)
        ; /** @type {VimDWin} */
        win := this.wins[winName]
        ;定义 hotwin
        if (winTitle == "")
            throw ValueError("winTitle is empty")
        HotIfWinActive(winTitle)
        win.arrWinTitles.push(winTitle)
        win.currentWinTitle := winTitle ;NOTE 做个标记未设置
        win.objRegisteredHotkeys[win.currentWinTitle] := map()
        ;定义cls(可选)，比如和 cls.getTitleEx 联动
        if (isset(cls))
            win.cls := cls
        return win
    }

    ;NOTE 运行出错后必须要执行此方法，否则下次 VimD 的第一个键会无效
    static ErrorHandler(str := "") {
        if (this.winCurrent)
            this.winCurrent.currentMode.init()
        if (str != "") {
            msgbox(A_ThisFunc . "`n" . str, , 0x40000)
            exit
        }
    }

    ;VimDMode.ShowTips
    static HideTips() {
        OutputDebug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
        tooltip(, , , VimD.tipLevel)
    }

    static SetDebugLevel() {
        VimD.debugLevel := !VimD.debugLevel
        status := VimD.debugLevel ? "显示" : "隐藏"
        tooltip(format("【{1}】调试信息", status))
        SetTimer(tooltip, -1000)
    }
    static HideTips1() => tooltip(, , , VimD.tipLevel1)
    static ShowTips1(str, x := 0, y := 0) => tooltip(str, x, y, VimD.tipLevel1) ;辅助显示，固定在某区域

    ;-----------------------------------key__-----------------------------------
    /*
    this.DictVimKey := map(
        "<LButton>","LButton", "<RButton>","RButton", "<MButton>","MButton",
        "<XButton1>","XButton1",   "<XButton2>","XButton2",
        "<WheelDown>","WheelDown", "<WheelUp>","WheelUp",
        "<WheelLeft>","WheelLeft", "<WheelRight>","WheelRight",
        键盘控制,
        "<CapsLock>","CapsLock", "<Space>","Space", "<Tab>","Tab",
        "<Enter>","Enter", "<Esc>","Escape", "<BS>","BackSpace",
        Fn,
        "<F1>","F1","<F2>","F2","<F3>","F3","<F4>","F4","<F5>","F5","<F6>","F6",
        "<F7>","F7","<F8>","F8","<F9>","F9","<F10>","F10","<F11>","F11","<F12>","F12",
        光标控制,
        "<ScrollLock>","ScrollLock", "<Del>","Del", "<Ins>","Ins",
        "<Home>","Home", "<End>","End", "<PgUp>","PgUp", "<PgDn>","PgDn",
        "<Up>","Up", "<Down>","Down", "<Left>","Left", "<Right>","Right",
        修饰键,
        "<Lwin>","LWin", "<Rwin>","RWin",
        "<control>","control", "<Lcontrol>","Lcontrol", "<Rcontrol>","Rcontrol",
        "<Alt>","Alt", "<LAlt>","LAlt", "<RAlt>","RAlt",
        "<Shift>","Shift", "<LShift>","LShift", "<RShift>","RShift",
        特殊键,
        "<Insert>","Insert", "<Ins>","Insert",
        "<AppsKey>","AppsKey", "<LT>","<", "<RT>",">",
        "<PrintScreen>","PrintScreen",
        "<controlBreak>","controlBrek",
    )
    ; 数字小键盘暂时不支持
    ; 功能键
    this.DictVimModifier := map(
        "S","shift", "LS","lshift", "RS","rshift &",
        "A","alt", "LA","lalt", "RA","ralt",
        "C","control", "LC","lcontrol", "RC","rcontrol",
        "W","lwin", "LW","lwin", "RW","lwin",
        "T","tab", "L","CapsLock", "E","Escape",
    )
    this.DictVimModifierSend := map(
        "S","+", "LS","+", "RS","+",
        "A","!", "LA","!", "RA","!",
        "C","^", "LC","^", "RC","^",
        "W","#", "LW","#", "RW","#",
    )
    */

    ;NOTE 用于内部逻辑判断
    ;从 ThisHotkey (VimD里map定义的键)提取 keyMap
    ;带修饰键
    ;   +a --> A
    ;   ^a --> <^a> 一般都直接执行
    ;多字符
    ;   space --> A_Space 不用{space}
    ;   enter --> {enter}
    ;   escape --> {escape}
    ;单字符
    ;   CapsLock则转换大小写
    ;   其他不处理
    static Hot2Map(ThisHotkey) {
        keyMap := ThisHotkey
        if (keyMap ~= "[+!#^].") { ;带修饰键
            keyMap := (keyMap ~= "^\+[a-z]$") ;大写字母 +a
                ? (GetKeyState("CapsLock", "T") ? substr(keyMap, -1) : StrUpper(substr(keyMap, -1)))
                : format("<{1}>", keyMap)
            ;} else if (ThisHotkey ~= "i)^[rl]\w+\s\&\s\S+") { ;LShift & a
            ;    keyMap := (ThisHotkey ~= "i)^[rl]shift\s\&\s[a-z]")
            ;        ? StrUpper(substr(ThisHotkey,-1))
            ;        : format("<{1}>", ThisHotkey)
        } else if (strlen(keyMap) > 1) {
            if (1) ;更符合用户查看方式
                keyMap := (ThisHotkey == "space") ? A_Space : format("{{1}}", ThisHotkey)
            else
                keyMap := format("{{1}}", keyMap)
        } else { ;长度=1
            if (GetKeyState("CapsLock", "T")) { ;大小写转换
                if (keyMap ~= "^[a-z]$")
                    keyMap := StrUpper(keyMap)
                else if (keyMap ~= "^[A-Z]$")
                    keyMap := StrLower(keyMap)
            }
        }
        return keyMap
    }

    ;keyMap := VimD.Hot2Map()
    static Map2Send(keyMap) {
        if (keyMap ~= "^<.+>")
            keyMap := substr(keyMap, 2, strlen(keyMap) - 2)
        else if (strlen(keyMap) == 1) ;支持大小写
            keyMap := (keyMap == " " ? "{space}" : format("{{1}}", keyMap))
        return keyMap
    }

    ; ;获取当前 hotif 指定的 WinTitle 字符串
    ; ;感谢【天黑请闭眼】大佬的支持
    ; static getHotIfWin() {
    ;     GlobalStruct := '
    ;     (
    ;         int64 mLoopIteration;
    ;         ptr mLoopFile;
    ;         ptr mLoopRegItem;
    ;         ptr mLoopReadFile;
    ;         LPTSTR mLoopField;
    ;         ptr CurrentFunc;
    ;         ptr CurrentMacro;
    ;         ptr CurrentTimer;
    ;         ptr hWndLastUsed;
    ;         int EventInfo;
    ;         ptr DialogHWND;
    ;         ptr DialogOwner;
    ;         ptr ThrownToken;
    ;         int ExcptMode;
    ;         uint LastError;
    ;         int Priority;
    ;         int UninterruptedLineCount;
    ;         int UninterruptibleDuration;
    ;         uint ThreadStartTime;
    ;         uint CalledByIsDialogMessageOrDispatchMsg;
    ;         bool IsPaused;
    ;         bool MsgBoxTimedOut;
    ;         bool CalledByIsDialogMessageOrDispatch;
    ;         bool AllowThreadToBeInterrupted;
    ;         ptr HotCriterion;
    ;         uint PeekFrequency;
    ;         int TitleMatchMode;
    ;         int WinDelay;
    ;         int ControlDelay;
    ;         int KeyDelay;
    ;         int KeyDelayPlay;
    ;         int PressDuration;
    ;         int PressDurationPlay;
    ;         int MouseDelay;
    ;         int MouseDelayPlay;
    ;         uint RegView;
    ;         int SendMode;
    ;         UINT Encoding;
    ;         int CoordMode;
    ;         bool TitleFindFast;
    ;         bool DetectHiddenWindows;
    ;         bool DetectHiddenText;
    ;         bool AllowTimers;
    ;         bool ThreadIsCritical;
    ;         UCHAR DefaultMouseSpeed;
    ;         bool StoreCapslockMode;
    ;         int SendLevel;
    ;         bool ListLinesIsEnabled;
    ;         ptr ExcptDeref;
    ;         BYTE ZipCompressionLevel;
    ;     )'
    ;     g := Struct(GlobalStruct, A_GlobalStruct)
    ;     if (!g.HotCriterion)
    ;         return
    ;     HotkeyCriterion := '
    ;     (
    ;         int Type;
    ;         LPTSTR WinTitle;
    ;         LPTSTR WinText;
    ;         LPTSTR OriginalExpr;
    ;         ptr Callback;
    ;         ptr NextCriterion;
    ;         ptr NextExpr;
    ;         uint ThreadID;
    ;     )'
    ;     hc := Struct(HotkeyCriterion, g.HotCriterion)
    ;     return hc.WinTitle
    ;     ;return ['HOT_NO_CRITERION', 'HOT_IF_ACTIVE', 'HOT_IF_NOT_ACTIVE', 'HOT_IF_EXIST', 'HOT_IF_NOT_EXIST', 'HOT_IF_CALLBACK'][hc.Type+1] . "`n" . hc.WinTitle . "`n" . hc.WinText . "`n" . hc.OriginalExpr
    ; }

    static checkInclude() {
        SplitPath(A_LineFile, , &dir)
        fp := format("{1}\VimDInclude.ahk", dir)
        str := fileread(fp)
        arr := StrSplit(rtrim(fileread(fp), "`r`n"), "`n", "`r").map(v => StrSplit(v, "\")[2])
        ;objInclude := StrSplit(rtrim(fileread(fp),"`r`n"), "`n", "`r").map(v=>)
        if (hyf_checkNewPlugin(A_WorkingDir "\VimDInclude.ahk", [[A_WorkingDir, "wins"
        ]], "VimD_")) {
            f := FileOpen(fp, "w", "utf-8-raw")
            strInclude := ""
            loop files, format("{1}\wins\*", A_LineFile.dir()), "D"
                strInclude .= format("#include wins\{1}\VimD_{1}.ahk`n", A_LoopFileName)
            f.write(strInclude)
            f.close()
        }
    }

}

;OnError(ErrorHandler)
;ErrorHandler(exception, mode) {
;    msgbox(exception.file . "`n" . exception.line,,0x40000)
;    VimD.ErrorHandler() ;NOTE 否则 VimD 下个按键会无效
;}

#include VimDInclude.ahk
#include VimDWin.ahk
#include VimDMode.ahk