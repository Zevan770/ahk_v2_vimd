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
    static groupKeymap := "groupString" ;分组的全局搜索时，action 的字段定义在 groupKeymap
    static groupStatus := false
    static groupKeyAll := "{F12}" ;NOTE 执行当前全部命令
    /** @type {Map<String, VimD.VimDWin>} */
    static wins := Map() ;在 initWin里设置

    static __new() {
        OutputDebug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
        ;HotIfWinActive ;TODO 关闭
    }

    ;NOTE 核心，由各插件自行调用
    static InitWin(winName, winTitle, cls := unset) {
        ;msgbox(winName . "`n" . json.stringify(this.wins, 4))
        if !this.wins.has(winName)
            this.wins[winName] := this.VimDWin(winName)
        ; /** @type {VimD.VimDWin} */
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

    ;窗口对象会直接生成两个默认的mode(changeMode获取)
    ;模式由各插件自行定义(生成+map一并进行)
    class VimDWin {
        __new(name) {
            ;主要属性
            this.name := name
            this.arrModes := [] ;默认2个模式
            this.arrWinTitles := [] ;记录所有 currentWinTitle
            this.arrActionHistory := [] ;记录所有已运行的命令
            this.lastAction := []
            ;this.modeList := map()
            this.currentMode := ""
            this.currentWinTitle := ""
            ;目的：单键在同个 HotIfWinActive 下不要重复【定义】(【使用】记录的对象在 VimDMode 属性里记录)
            ;用任意模式【定义一次hotkey】即可(是否要特殊考虑第一个按键？)，能拦截到，后续由 keyIn 处理逻辑
            this.objRegisteredHotkeys := map()
            this.objRegisteredHotkeys.CaseSense := true
            ;其他属性
            this.count := 0
            this.skipRepeat := false ;无视count
            this.isRepeat := false
            this.skipRepeat := "" ;获取 tooltip 的坐标
            ;event(部分事件在 VimDWin 部分事件在 VimDMode)
            this.onBeforeChangeMode := ""
            this.onAfterChangeMode := ""
            ;this.onBeforeMap := ""
            ;this.onAfterMap := ""
            this.onBeforeShowTip := ""
            this.onBeforeHideTip := ""
            ;搭配 superKey 使用
            this.superKey := ""
            this.Mode0key := "``" ;如果设置为空，则无法切换至 mode0
            this.keyToMode1 := "{escape}" ;如果设置为空，则无法切换至 mode1，只用<super>键功能执行 mode1 命令
            this.keyDebug := "{F10}" ;用得较少 {F12}一般用在配置文件
            this.superModeType := 0 ;1=只切换 2=切换并执行按键
            this.superKeys := map() ;记录超级按键，比 superKey 多了个生效当前按键功能
        }

        ;初始化内置的模式(mode0|mode1)
        ;此方法由各插件调用(生成+map一并进行)
        ;默认的模式放最后定义，或者最后加上 win.SwitchMode(i)
        ;NOTE 必须先 SetHotIf
        ;binMap(二进制理解) 0=none 1=count 2=repeat 3=both
        InitMode(idx, binMap := 3, funOnBeforeKey := false, modename := "") {
            if (this.currentWinTitle == "")
                throw ValueError('request "SetHotIf" done')
            ;mode0 未定义，则自动定义
            if (idx == 1 && this.arrModes.length == 0)
                this.InitMode(0)
            this.currentMode := VimD.VimDMode(idx, this, modename) ;modename 用来修改内置模式名
            if (this.arrModes.length < idx + 1)
                this.arrModes.push(this.currentMode)
            else
                this.arrModes[idx + 1] := this.currentMode
            ;NOTE 在这里直接定义 InitWin 时设置的 currentWinTitle
            this.currentMode.MapDefault(binMap)
            if (funOnBeforeKey)
                this.currentMode.onBeforeKey := isobject(funOnBeforeKey) ? funOnBeforeKey : ObjBindMethod(this.currentMode,
                    "BeforeKey")
            return this.currentMode
        }

        GetMode(i := unset) {
            if (!IsSet(i))
                return this.currentMode
            else
                return this.arrModes[i + 1]
        }
        SetMode(i) => this.currentMode := this.GetMode(i)

        ;指定后面热键的窗口(大部分是针对ahk_class的)
        ;NOTE bAsHotIfWin 推荐 false
        ;   如果全为true，则会存在抢热键的情况，单个键只能在一个窗口生效，【先定义】的 HotIfWin 优先，所以要考虑兼容性问题
        ;   如果为 false，热键仍然生效，菜单仍会出现，可根据 objHotIfWins[winTitle] 的数组自由组合
        ;VimD.InitWin 内容较多，这是纯净版
        SetHotIf(winTitle, bAsHotIfWin := true) {
            this.arrWinTitles.push(winTitle)
            ;定义 VimDWin 的属性
            this.currentWinTitle := winTitle
            this.objRegisteredHotkeys[this.currentWinTitle] := map()
            if (bAsHotIfWin)
                HotIfWinActive(winTitle)
        }

        ;超级模式
        ;md 1=只切换 2=切换并执行按键
        ;TODO 热键由 mode0 接入，所有的代码属性都是 mode0 的，如何处理？
        EnterSuperMode(md := 1, bTooltip := false) {
            if (this.superModeType == md && bTooltip) {
                tooltip(format("don't repeat!`nmodeBeforeSuper = {1}", this.modeBeforeSuper.name))
                SetTimer(tooltip, -1000)
                return
            }
            this.superModeType := md
            ;记录之前的模式，后续恢复用
            this.modeBeforeSuper := this.currentMode
            this.currentMode := this.GetMode(1)
            if (bTooltip) {
                tooltip(format("modeBeforeSuper = {1}", this.modeBeforeSuper.name))
                SetTimer(tooltip, -1000)
            }
        }
        ExitSuperMode() {
            if (this.superModeType == 1) {
                tooltip(this.modeBeforeSuper.name)
                SetTimer(tooltip, -1000)
            }
            this.superModeType := 0
            ;记录之前的模式，后续恢复用
            this.currentMode := this.DeleteProp("modeBeforeSuper")
        }

        ;NOTE 至少需要初始化一个模式
        ;NOTE 模式不能自动识别的才需要
        SetSuperKey(superKey := "{RControl}") {
            ;标记此键
            this.superKey := superKey
            ;VimD 拦截此键，功能为切换到 super mode1(不判断 onBeforeKey，结束用 superModeType 来全局判断)
            this.currentMode.MapKey(superKey, ObjBindMethod(this, "SwitchMode", 1), "super mode1")
        }

        ;临时把 count 当值使用(默认是执行 count 次功能)
        ;方便插件调用
        SetSkipRepeat(cntDefault := 1) {
            this.skipRepeat := true
            if (this.isRepeat)
                cnt := this.lastAction[2]
            else
                cnt := this.GetCount(cntDefault)
            OutputDebug(format("i#{1} {2}:SetSkipRepeat cnt={3}", A_LineFile, A_LineNumber, cnt))
            return cnt
        }

        GetCount(cntDefault := 1) => this.count ? this.count : cntDefault ;执行时用(默认返回1，而用count属性默认为0)

        ;设置currentMode，不存在会自动new
        ;由于会触发事件，所以不能在初始化时使用，很可能找不到窗口出错
        ;i 从0开始
        SwitchMode(i) {
            if (this.onBeforeChangeMode)
                this.onBeforeChangeMode.call(this.currentMode)
            tooltip((this.superModeType == 1 ? "super " : "") . this.SetMode(i).name)
            SetTimer(tooltip, -1000)
            if (this.onAfterChangeMode) ;TODO 一般用来修改样式让用户清楚当前在哪个模式
                this.onAfterChangeMode.call(this.currentMode)
            return this.currentMode
        }

        ;NOTE 由 VimDWin 对象接收按键并调度
        ;这里只处理特殊情况
        ;由 _keyIn() 处理后续细节
        ;byScript 非手工按键，而是用脚本触发时，需要传入此参数，如 VimD_WeChat.win.keyIn("F3", "ahk_exe WeChat.exe")
        keyIn(ThisHotkey, byScript := 0) {
            keyMap := VimD.Hot2Map(ThisHotkey)

            ;OutputDebug(format("i#{1} {2}:A_ThisFunc={3}-------------------start", A_LineFile,A_LineNumber,A_ThisFunc))
            ;OutputDebug(format("currentMode.index={1}", this.currentMode.index))
            ;OutputDebug(format("arrKeyPressed.length = {1}", this.currentMode.arrKeyPressed.length))
            ;OutputDebug(format("keyMap={1}", keyMap))
            ;OutputDebug(format("superModeType = {1}", this.superModeType ))
            ;OutputDebug(format("superKeys={1}", json.stringify(this.superKeys)))
            ;OutputDebug(format("i#{1} {2}:A_ThisFunc={3}-------------------end", A_LineFile,A_LineNumber,A_ThisFunc))
            ;NOTE 记录当前的窗口，用来出错后 init
            VimD.winCurrent := this
            this.currentMode._keyIn(keyMap, byScript)
            if (this.currentMode.onAfterKey)
                this.currentMode.onAfterKey.call(keyMap)
        }

    }

    ;TODO mode暂时不支持子窗口
    ;-----------------------------------maps-----------------------------------
    ;-----------------------------------do__-----------------------------------
    ;-----------------------------------tip-----------------------------------
    class VimDMode {
        ; /** @type VimD.VimDMode */
        win := unset

        __new(idx, win, modename := "") {
            this.index := idx
            this.win := win ;标记是哪个窗口的mode
            if (idx > 1)
                VimD.arrModeName.push(modename != "" ? modename : format("mode{1}", idx))
            else if (modename != "") ;修改内置模式名
                VimD.arrModeName[this.index + 1] := modename
            this.name := this.win.name . "-" . VimD.arrModeName[this.index + 1]
            this.objTips := map() ;NOTE 大纲提示(可动态在命令里用 this.mode1.objTips[key] 来添加)
            this.objTips.CaseSense := true
            this.objDynamicHandlers := map() ;记录所有需要验证动态信息的按键(可以快速过滤无关按键)
            this.objDynamicHandlers.CaseSense := true
            ;NOTE objHotIfWin_xxx 对象，都先定义了 key1 = currentWinTitle(为了支持子窗口)
            this.actions := map() ;{keysmap, action}
            this.actions.CaseSense := true
            ;每个key 后的value 都分normal|dynamic|group(若有)
            this.leaderKey2ActionMap := map()
            ;先根据窗口区分执行，再通过第1个热键分隔
            ;this.objHotIfWins := map() ;记录当前子窗口的关联窗口名
            ;this.thisHotIfWin := "" ;以第一个键判断当前匹配窗口(解决窗口乱匹配，导致热键识别问题)
            ;NOTE 用 array 可以记录顺序
            ;event(部分事件在 VimDWin 部分事件在 VimDMode)
            ;NOTE 智能判断按键(智能模式识别的核心)返回 false 则直接发送按键
            ;NOTE 如果是第2个键则不进行判断
            this.onBeforeKey := ""
            this.onAfterKey := ""
            this.onBeforeDo := ""
            this.onAfterDo := ""
            ;NOTE NOTE NOTE 在 None 模式下临时切换为 Vim <2022-07-28 15:00:47>
            ;按键定义参考 Hot2Map 返回值
            this.superKey := ""
            this.arrKeyPressed := [] ;记录每个按键
            this.arrDynamicTips := []
        }

        ;脚本运行过程出错，要先运行此命令退出，否则下次按键会因为 arrKeyPressed 误判(往往使下一按键无效)
        ;NOTE 执行命令或中途退出才执行
        ;tp -1=执行前半段 0=全部执行 1=执行后半段
        init(tp := 0) {
            ;OutputDebug(format("i#{1} {2}:init tp={3} start", A_LineFile,A_LineNumber,tp))
            if (tp <= 0) { ;用于在do之前先初始化一部分
                if (this.arrKeyPressed.length && this.leaderKey2ActionMap.has(this.arrKeyPressed[1]) && this.leaderKey2ActionMap[this.arrKeyPressed[
                    1]].has("group"))
                    this.leaderKey2ActionMap[this.arrKeyPressed[1]].delete("group")
                this.arrKeyPressed := [] ;记录每个按键
                this.arrDynamicTips := []
                VimD.groupStatus := false
                if (this.win.superModeType)
                    this.win.ExitSuperMode()
                VimD.HideTips1()
                VimD.HideTips()
            }
            if (tp >= 0) { ;影响执行逻辑的属性
                this.win.count := 0
                this.win.isRepeat := false
                this.win.skipRepeat := false
            }
        }

        ;NOTE 设置关联，适合复杂逻辑，否则用 SetHotIf 即可
        ;TODO 尽量不用，用 setDynamics 来实现动态 <2023-03-24 18:56:52> hyaray
        setObjHotWin(winTitle, bAsHotIfWin := true, arrWinTitle := unset) {
            this.win.SetHotIf(winTitle, bAsHotIfWin)
        }

        ;NOTE 这个只是方便调用，方法名格式为 dynamicF1
        setDynamics(arr, cls) {
            for key in arr {
                key1 := VimD.Hot2Map(key)
                this.setDynamic(format("<super>{{1}}", key), ObjBindMethod(cls, "dynamic" . key, key1))
            }
        }

        ;objFun 如果有true的返回值，则直接 init 结束
        setDynamic(key, objFun) {
            if instr(key, "<super>") {
                key := StrReplace(key, "<super>")
                this.win.superKeys[key] := 1
            }
            this.objDynamicHandlers[key] := objFun
            this._Map(key) ;NOTE 定义的时候必须要确保 key 在拦截清单内
        }

        ;NOTE 被keyIn调用
        _keyIn(keyMap, byScript, checkSuper := true) {
            ;第一个按键
            if (this.arrKeyPressed.length == 0) {
                ;无视模式的按键
                if (keyMap == this.win.superKey) { ;如 {RControl}
                    this.win.EnterSuperMode(1, true)
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} is superKey", A_LineFile, A_LineNumber, A_ThisFunc))
                    exit
                } else if (checkSuper && this.win.superKeys.has(keyMap)) { ;<super>
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} {4} is <super>", A_LineFile, A_LineNumber, A_ThisFunc, keyMap
                        ))
                    this.win.EnterSuperMode(2)
                    this.win.currentMode._keyIn(keyMap, byScript, false) ;NOTE 以 mode1 运行
                    exit
                }
                ;NOTE 判断当前匹配窗口 UpdateState 用
                ;this.thisHotIfWin := (byScript==0) ? VimD.getHotIfWin() : this.win.arrWinTitles[1] ;NOTE 不太准确，可能两个窗口都定义了此按键
                ;4. 判断 onBeforeKey
                if (this.win.superModeType == 0 && isobject(this.onBeforeKey)) { ;NOTE superModeType 则不执行 onBeforeKey
                    if (this.onBeforeKey.call(keyMap) == 0) { ;返回 false，则相当于 None 模式
                        if (VimD.debugLevel > 0)
                            OutputDebug(format("i#{1} {2}:{3} keyMap={4} onBeforeKey false", A_LineFile, A_LineNumber,
                                A_ThisFunc, keyMap))
                        send(VimD.Map2Send(keyMap))
                        exit
                    }
                }
                ;if (this.win.superModeType == 2) ;<super>键显示保存的模式名
                ;    this.AddDynamicTip(this.win.modeBeforeSuper.name)
                ;自动运行 objDynamicHandlers()
                if (this.HasOwnProp("objDynamicHandlers") && this.objDynamicHandlers.has(keyMap)) {
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} {4}.objDynamicHandlers({5})", A_LineFile, A_LineNumber, A_ThisFunc,
                            this.name, keyMap))
                    if (this.leaderKey2ActionMap.has(keyMap))
                        this.leaderKey2ActionMap[keyMap]["dynamic"] := [] ;NOTE 每次都要清空
                    if (this.objDynamicHandlers[keyMap]()) { ;TODO 特意有返回值的，表示已执行完动作，直接结束 <2023-01-20 22:25:39> hyaray
                        this.init()
                        exit
                    }
                    ;OutputDebug(format("i#{1} {2}:{3} dynamic={4}", A_LineFile,A_LineNumber,A_ThisFunc,json.stringify(this.leaderKey2ActionMap[keyMap]["dynamic"],4)))
                } else {
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} 键没有动态", A_LineFile, A_LineNumber, keyMap))
                }
                ;非常规功能
                if (this.actions.has(keyMap)) { ;单键功能
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:this.actions.has({3}) comment={4}", A_LineFile, A_LineNumber,
                            keyMap, this.actions[keyMap]["comment"]))
                    if (keyMap ~= "^\d$") {
                        this.HandleCount(integer(keyMap)) ;因为要传入参数，所以单独处理
                    } else if (keyMap == "{BackSpace}") {
                        this.doGlobal_BackSpace() ;因为无需 init，所以单独处理
                    } else if (keyMap == ".") {
                        this.init(-1)
                        this.doGlobal_Repeat() ;一般是 Exec(action["action"], this.win.GetCount())，repeat 刚好相反
                        this.init(1)
                    } else {
                        this.init(-1)
                        this.Exec(this.actions[keyMap]["action"], this.win.GetCount(), this.actions[keyMap][
                            "comment"])
                        this.init(1)
                    }
                    exit
                } else {
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("d#{1} {2}:this.actions.not has({3}) index={4}", A_LineFile, A_LineNumber,
                            keyMap, this.index))
                    if (this.index == 0) {
                        send(VimD.Map2Send(keyMap))
                    } else {
                        this.UpdateState(keyMap)
                    }
                }
            } else {
                this.UpdateState(keyMap)
            }
        }

        ;更新当前匹配的命令并 ShowTips
        ;先修改arrKeymapPressed再运行
        UpdateState(keyMap?) {
            ;OutputDebug(format("i#{1} {2}:{3} keyMap={4}", A_LineFile,A_LineNumber,A_ThisFunc,keyMap))
            if (keyMap == "{BackSpace}") {
                if (!this.UpdateKeySeq().length) {
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} no key", A_LineFile, A_LineNumber, A_ThisFunc))
                    this.init()
                    return
                } else if (this.leaderKey2ActionMap[this.arrKeyPressed[1]].has("group")) {
                    if (this.arrKeyPressed.length == 1) { ;分组会提示
                        VimD.groupStatus := false ;NOTE 切换回普通状态
                        this.AddDynamicTip()
                    }
                }
            } else if (keyMap == "{escape}") {
                this.init()
                return
            } else {
                this.UpdateKeySeq(keyMap)
            }
            ;NOTE 核心：获取匹配项
            arrMatch := getMatchAction()
            ;处理逻辑
            switch arrMatch.length {
                case 0: ;没找到命令
                    if (this.arrKeyPressed.length == 1) { ;为第1个按键
                        if (VimD.debugLevel > 0)
                            OutputDebug(format("i#{1} {2}:{3} send({4})", A_LineFile, A_LineNumber, A_ThisFunc, this.arrKeyPressed[
                                1]))
                        send(this.arrKeyPressed[1])
                        this.init()
                    } else if (keyMap ~= "^[1-9]$") { ;NOTE 按了不存在的数字键，当序号使用 <2023-01-20 23:34:18> hyaray
                        this.UpdateKeySeq()
                        ;重新获取匹配命令
                        i := integer(keyMap)
                        arrMatch := getMatchAction()
                        if (i <= arrMatch.length) {
                            this.init(-1)
                            this.Exec(arrMatch[i]["action"], this.win.GetCount(), arrMatch[i]["comment"])
                            this.init(1)
                        }
                    } else { ;TODO 按错了，忽略
                        this.UpdateKeySeq()
                    }
                case 1: ;单个结果
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} 1 matched={4}", A_LineFile, A_LineNumber, A_ThisFunc,
                            arrMatch[1]["comment"]))
                    this.init(-1)
                    this.Exec(arrMatch[1]["action"], this.win.GetCount(), arrMatch[1]["comment"])
                    this.init(1)
                default: ;大部分情况
                    this.ShowTips(arrMatch)
            }
            ;所有匹配热键(dynamic+normal)
            getMatchAction() {
                if (VimD.debugLevel > 0)
                    OutputDebug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
                ;按键未定义功能
                if (!this.leaderKey2ActionMap.has(this.arrKeyPressed[1])) {
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} first key not matched", A_LineFile, A_LineNumber, A_ThisFunc))
                    return []
                }
                ;常规情况
                if (!this.leaderKey2ActionMap[this.arrKeyPressed[1]].has("group")) {
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} first key no group", A_LineFile, A_LineNumber, A_ThisFunc))
                    return _matchAction()
                }
                ;NOTE group 情况
                switch this.arrKeyPressed.length {
                    case 1: ;首个按键，只显示分组功能
                        arrMatch := _matchAction(1)
                        if (arrMatch.length == 1) { ;只有1组，则直接展开下级
                            if (VimD.debugLevel > 0)
                                OutputDebug(format("i#{1} {2}:{3} only 1 group, groupStatus", A_LineFile, A_LineNumber,
                                    A_ThisFunc))
                            arrMatch := groupLoadGlobal(true)
                        }
                    case 2: ;第2按键
                        if (VimD.groupStatus) { ;已经展开了全局
                            arrMatch := groupLoadGlobal()
                        } else { ;搜索分组
                            arrMatch := _matchAction(2)
                            if (!arrMatch.length) { ;TODO 找不到分组，搜索全部分组下的节点
                                if (VimD.debugLevel > 0)
                                    OutputDebug(format("i#{1} {2}:{3} group not matched", A_LineFile, A_LineNumber,
                                        A_ThisFunc))
                                arrMatch := groupLoadGlobal(true) ;分组下的节点仍搜不到，仍给上级处理
                                ;if (!arrMatch.length)
                                ;    this.UpdateKeySeq()
                            } else {
                                this.AddDynamicTip(format("{1}`t按{2}执行全部功能", "", VimD.groupKeyAll))
                            }
                        }
                    default: ;3-n个按键
                        if (VimD.groupStatus) { ;已经展开了全局
                            arrMatch := _matchAction(2, VimD.groupKeymap)
                        } else { ;仍然分组搜索
                            OutputDebug(format("i#{1} {2}:{3} group", A_LineFile, A_LineNumber, A_ThisFunc))
                            arrMatch := _matchAction()
                            groupDoAll()
                        }
                }
                if (VimD.debugLevel > 0)
                    OutputDebug(format("i#{1} {2}:{3} arrMatch={4}", A_LineFile, A_LineNumber, A_ThisFunc, json.stringify(
                        arrMatch, 4)))
                return arrMatch
                groupLoadGlobal(bAddTip := false) { ;跳过分组，直接加载全局命令
                    OutputDebug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
                    VimD.groupStatus := true
                    arrMatch := _matchAction(2, VimD.groupKeymap)
                    if (!arrMatch.length) { ; ;NOTE 子命令也不匹配，已经到了逻辑末尾，这里直接处理
                        if (!groupDoAll()) {
                            VimD.groupStatus := false
                            this.UpdateKeySeq()
                            exit
                        }
                    }
                    if (bAddTip)
                        this.AddDynamicTip(format("{1}`t按{2}执行全部功能", "", VimD.groupKeyAll))
                    return arrMatch
                }
                groupDoAll() { ;判断是否按键执行分组下所有命令
                    OutputDebug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
                    if (this.arrKeyPressed[-1] == VimD.groupKeyAll) {
                        this.UpdateKeySeq()
                        arrMatch := _matchAction(2)
                        this.init(-1)
                        for action in arrMatch
                            this.Exec(action["action"], this.win.GetCount())
                        this.init(1)
                        exit
                    } else {
                        return false
                    }
                }
                ;NOTE 分组情况下，如果全局搜子节点，会删除分组的热键(场景：不知道在哪个全组，所以才全局搜索)
                _matchAction(groupLevel := 0, key := "string") {
                    arrTmp := []
                    objUnique := map()
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} this.sKeyPressed={4} key={5}", A_LineFile, A_LineNumber,
                            A_ThisFunc, this.sKeyPressed, key))
                    for tp in ["dynamic", "normal"
                    ] {
                        if (!this.leaderKey2ActionMap[this.arrKeyPressed[1]].has(tp))
                            continue
                        if (VimD.debugLevel > 0)
                            OutputDebug(format("i#{1} {2}:{3} tp={4} {5}", A_LineFile, A_LineNumber, A_ThisFunc, tp,
                                json.stringify(this.leaderKey2ActionMap[this.arrKeyPressed[1]][tp], 4)))
                        for action in this.leaderKey2ActionMap[this.arrKeyPressed[1]][tp] {
                            if (key == VimD.groupKeymap && !action.has(key))
                                continue
                            if (instr(action[key], this.sKeyPressed, true) == 1) { ;NOTE 匹配大小写
                                if (groupLevel) {
                                    ;if (groupLevel == 2 && action["groupLevel"] == 1)
                                    ;VimD.groupCurrent := action["commentClean"]
                                    ;msgbox(json.stringify(action, 4))
                                    if (action["groupLevel"] == groupLevel) {
                                        if (groupLevel == 2) { ;NOTE 同命令可能在多个分组下有重复，以注释为依据去重
                                            if (objUnique.has(action["comment"]))
                                                continue
                                            else
                                                objUnique[action["comment"]] := 1
                                        }
                                        arrTmp.push(action)
                                    }
                                } else {
                                    arrTmp.push(action)
                                }
                            }
                        }
                    }
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("i#{1} {2}:{3} arrMatch={4}", A_LineFile, A_LineNumber, A_ThisFunc, json.stringify(
                            arrTmp, 4)))
                    return arrTmp
                }
            }
        }

        HandleCount(keyMap) {
            if (keyMap == "{BackSpace}") {
                if (this.win.count > 9) { ;两位数
                    this.win.count := this.win.count // 10
                    OutputDebug(format("i#{1} {2}:this.win.count={3}", A_LineFile, A_LineNumber, this.win.count))
                } else {
                    this.init()
                    return
                }
            } else {
                this.win.count := this.win.count ? this.win.count * 10 + integer(keyMap) : integer(keyMap)
            }
            this._ShowTip(string(this.win.count))
        }

        ;NOTE 会同时更新 this.sKeyPressed
        UpdateKeySeq(k := "") {
            (k == "") ? this.arrKeyPressed.pop() : this.arrKeyPressed.push(k)
                this.sKeyPressed := "".join(this.arrKeyPressed) ;TODO 是否直接修改
                if (VimD.debugLevel > 0)
                    OutputDebug(format("i#{1} {2}:{3} arrKeyPressed={4}", A_LineFile, A_LineNumber, A_ThisFunc, json
                        .stringify(this.arrKeyPressed, 4)))
                return this.arrKeyPressed
        }

        ;-----------------------------------maps-----------------------------------

        ;action 来源于 Map2ArrHot
        ;公共 map
        MapDefault(binMap) {
            if (this.index == 0) { ;mode0
                if (this.win.keyToMode1 != "")
                    this.MapKey(this.win.keyToMode1, ObjBindMethod(this, "doGlobal_Escape"), "进入 mode1")
            } else if (this.index == 1) { ;mode1
                this.MapKey("{escape}", ObjBindMethod(this, "doGlobal_Escape"), "escape")
                this.MapKey("{BackSpace}", ObjBindMethod(this, "doGlobal_BackSpace"), "BackSpace")
                ;由于这次模式还没生成，如果这两个键定义在 win 的属性
                if (this.win.Mode0key != "")
                    this.MapKey(this.win.Mode0key, ObjBindMethod(this.win, "SwitchMode", 0), "进入 mode0")
                ;NOTE 定义debug的内置功能，自带 <super> 参数
                this.MapKey(format("<super>{1}{1}", this.win.keyDebug), ObjBindMethod(this, "doGlobal_Edit"),
                "【编辑】VimD_" . this.win.name)
                this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "d"), ObjBindMethod(VimD, "SetDebugLevel"),
                "显示/隐藏调试信息")
                this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "["), ObjBindMethod(this, "doGlobal_objFKey"),
                "查看所有功能(按首键分组)leaderKey2ActionMap")
                this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "]"), ObjBindMethod(this, "doGlobal_objKeysmap"),
                "查看所有功能(按keymap分组)actions")
                this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "k"), ObjBindMethod(this,
                    "doGlobal_Debug_objSingleKey"), "查看所有拦截的按键 objRegisteredHotkeys")
                this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "|"), ObjBindMethod(this,
                    "doGlobal_Debug_objKeySuperVim"), "查看所有的<super>键 superKeys")
                this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "\"), ObjBindMethod(this,
                    "doGlobal_Debug_objFunDynamic"), "查看所有的<super>键 objDynamicHandlers")
                this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "/"), ObjBindMethod(this,
                    "doGlobal_Debug_arrHistory"), "查看运行历史 arrActionHistory")
                n := 0 ;二进制的位数<super>(从右开始)
                if ((binMap & 2 ** n) >> n) ;也可以用 "10" 这种字符串来判断
                    this.MapCount()
                n++
                if ((binMap & 2 ** n) >> n)
                    this.MapKey(".", "", "重做")
            }
        }
        MapCount() {
            loop (10)
                this.MapKey(string(A_Index - 1), "", format("<{1}>", A_Index - 1))
        }

        ;显性为分组做准备，否则每次 MapKey 都要判断是否已完成
        ;只判断有无key，值没用
        DefineGroup(k0) {
            if (this.leaderKey2ActionMap.has(k0))
                this.leaderKey2ActionMap[k0]["group"] := 0
            else
                this.leaderKey2ActionMap[k0] := map("group", 0)
        }

        ;keysmap类型 <^enter> {F1} + A
        MapKey(keysmap, funcObj := unset, comment := unset, groupLevel := 0) {
            this._Map(keysmap, funcObj?, comment?, groupLevel, "normal")
        }
        mapDynamic(keysmap, funcObj := unset, comment := unset, groupLevel := 0) {
            this._Map(keysmap, funcObj?, "***" . comment, groupLevel, "dynamic") ;TODO 动态功能，是否要标识
        }
        ;arr2 格式
        ; [
        ;   [groupName, groupHot], ;第1项为分组
        ;   [
        ;       [item1Name, item1Hot],
        ;       [item2Name, item2Hot],
        ;   ]
        ;]
        MapGroup(hotBefore, fun, arr2, sBefore := "") {
            groupName := format("{1}【{2}】", sBefore, arr2[1][1])
            if (arr2[2].length == 1) { ;只有1项子元素，则直接显示到分组上
                switch arr2[2][1].length {
                    case 0: return
                    case 1, 2:
                        groupName .= "--" . arr2[2][1][1]
                    default:
                        groupName .= "--" . arr2[2][1][3]
                }
            }
            this.mapDynamic(hotBefore . arr2[1][2], , groupName, 1)
            for arrTmp in arr2[2] {
                hot := hotBefore . arr2[1][2]
                switch arrTmp.length {
                    case 1:
                        name := arrTmp[1]
                        hot .= string(A_Index) ;默认序号
                    case 2:
                        name := arrTmp[1]
                        hot .= arrTmp[2]
                    default:
                        name := arrTmp[3]
                        hot .= (arrTmp[2] == "") ? string(A_Index) : arrTmp[2]
                }
                this.mapDynamic(hot, fun.bind(arrTmp[1]), name, 2)
            }
        }
        ;把定义打包为 action
        ;如果 funcObj 在 keyIn 里明确了逻辑，则这里随便定义都行，比如 MapCount
        ;NOTE 在 setDynamic 只传入第1个参数，为了拦截热键而已
        ;groupLevel 0=普通 1=分组 2=功能
        _Map(keysmap, funcObj := unset, comment := unset, groupLevel := 0, tp := "normal") {
            action := this.Map2ArrHot(keysmap, groupLevel)
            if (isset(comment)) {
                if (isset(funcObj))
                    action["action"] := funcObj
                if (comment is array) {
                    action["comment"] := comment[1] . comment[2]
                    action["commentClean"] := comment[2] ;NOTE 仅分组定义
                } else {
                    action["commentClean"] := action["comment"] := comment
                }
                action["hotwin"] := this.win.currentWinTitle
                action["groupLevel"] := groupLevel
                if (!this.leaderKey2ActionMap.has(action["leaderKey"]))
                    this.leaderKey2ActionMap[action["leaderKey"]] := map(tp, [action
                    ])
                else if (!this.leaderKey2ActionMap[action["leaderKey"]].has(tp))
                    this.leaderKey2ActionMap[action["leaderKey"]][tp] := [action
                    ]
                else
                    this.leaderKey2ActionMap[action["leaderKey"]][tp].push(action)
                this.actions[action["string"]] := action
                ;if (this.win.name = "notepad" && action["leaderKey"] = "{F9}")
                ;    msgbox(json.stringify(action, 4))
            }
            for key in action["arrkey"] {
                if (A_Index == 1 && action["super"]) ;记录超级键
                    this.win.superKeys[VimD.Hot2Map(key)] := 1
                if (!this.win.objRegisteredHotkeys[this.win.currentWinTitle].has(key)) { ;单键避免重复定义
                    hotkey(key, ObjBindMethod(this.win, "keyIn")) ;NOTE 相关的键全部拦截，用 VimD 控制
                    this.win.objRegisteredHotkeys[this.win.currentWinTitle][key] := 1
                }
            }
            return action
        }

        ;NOTE 和 VimD.Hot2Map() 相反，只用于转换用户定义的按键为 VimD 格式
        ;keysmap类型 <^enter> {F1} + A
        ;插件里定义的 keyMap(尽量兼容hotkey) 转成 hotkey 命令识别的格式的数组
        ;返回 arr(比如 <^a>A{enter}，则返回["^a","+a","enter"])
        ;带修饰键(一般都直接执行)
        ;   <^f> --> ^f
        ;多字符
        ;   {F1} --> F1
        ;单字符
        ;   空格 --> space
        ;   不处理
        ;二次处理
        ;   A --> +a
        ;返回 action 的初步结果，后续由 _Map 完善
        ;["arrkey"] := []
        ;["leaderKey"] := [] ;第1个按键
        ;["string"] := "" ;按键字符串
        ;[groupKeymap] := "" ;分组按键字符串
        ;["hotwin"] := "" ;NOTE 记录按键当前的窗口，实际上因为按键冲突，没用
        ;["action"] := ""
        ;["comment"] := ""
        ;["commentClean"] := "" ;NOTE 显示分组名称 by 火冷 <2023-04-24 08:52:21>
        ;["super"] := super ;热键永远 on(无视模式)，直接用 hotkey()定义即可
        Map2ArrHot(keysmap, groupLevel) {
            ;keysmap := RegExReplace(RegExReplace(RegExReplace(keysmap, "i)<super>", "", &super), "i)<noWait>", "", &noWait), "i)<noMulti>", "", &noMulti)
            keysmap := RegExReplace(keysmap, "i)<super>", "", &isSuper)
            action := map(
                "arrkey", [], ;hotkey命令用
                "super", isSuper,
                "string", keysmap,
            )
            if (groupLevel > 1)
                action[VimD.groupKeymap] := "" ;删除分组热键(第2个按键)
            ;msgbox(json.stringify(action, 4))
            while (keysmap != "") {
                ;优先提取<>组合键，<^a>
                if (RegExMatch(keysmap, "^<.+?>", &m)) {
                    thisKey := substr(keysmap, 2, m.Len(0) - 2) ;^a
                    keysmap := substr(keysmap, m.Len(0) + 1)
                    if (A_Index == 1)
                        action["leaderKey"] := m[0]
                } else if (RegExMatch(keysmap, "^\{.+?\}", &m)) { ;{F1}
                    thisKey := substr(keysmap, 2, m.Len(0) - 2) ;F1
                    keysmap := substr(keysmap, m.Len(0) + 1)
                    if (A_Index == 1)
                        action["leaderKey"] := m[0]
                } else {
                    thisKey := substr(keysmap, 1, 1)
                    keysmap := substr(keysmap, 2)
                    if (A_Index == 1)
                        action["leaderKey"] := thisKey
                }
                ;添加 VimD.groupKeymap
                if (groupLevel > 1 && A_Index != 2)
                    action[VimD.groupKeymap] .= VimD.Hot2Map(thisKey)
                ;二次处理
                if (thiskey == " ")
                    thisKey := "space"
                else if (thisKey ~= "^[A-Z]$") ;大写字母单个大写字母转成 +a
                    thisKey := "+" . StrLower(thisKey)
                action["arrkey"].push(thisKey)
            }
            ;if (groupLevel > 1)
            ;    msgbox(json.stringify(action, 4))
            return action
        }

        ;getmap(sKey) {
        ;}

        ;-----------------------------------do__-----------------------------------
        BeforeKey(p*) => !CaretGetPos() ;有些软件要用 UIA.GetFocusedElement().CurrentControlType != UIA.ControlType.Edit

        ;doSend(key) {
        ;    if GetKeyState("CapsLock")
        ;        send(format("{shift down}{1}{shift up}", key))
        ;    else
        ;        send(key)
        ;}

        ;最终执行的命令
        ;因为 doGlobal_Repeat 调用，所以把 cnt 放参数
        ;为什么第一个参数不用 action
        Exec(varDo, cnt, comment := unset) {
            ;处理 repeat 和 count
            if (!this.win.isRepeat) {
                this.win.lastAction := [varDo, cnt, comment?
                ] ;this.sKeyPressed
                this.win.arrActionHistory.push(this.win.lastAction)
            }
            ;timeSave := A_TickCount
            if (VimD.debugLevel > 0)
                OutputDebug(format("d#{1} {2}:{3} count={4}", A_LineFile, A_LineNumber, A_ThisFunc, cnt))
            ;NOTE 运行
            loop (cnt) {
                this.ExecAction(varDo, true)
                if (this.win.skipRepeat) { ;运行后才知道是否 skipRepeat
                    if (VimD.debugLevel > 0)
                        OutputDebug(format("d#{1} {2}:break", A_LineFile, A_LineNumber))
                    break
                }
            }
            ;tooltip(A_TickCount - timeSave,,, 9)
            ;SetTimer(tooltip.bind(,,, 9), -1000)
            if (isobject(this.onAfterDo))
                this.ExecAction(this.onAfterDo)
        }

        ;NOTE 这里不能初始化 skipRepeat
        ;网址没在内
        ExecAction(funcObj, errExit := false) {
            if !(funcObj is string) {
                funcObj()
                return true
            }
            try {
                if (type(%funcObj%).isFunc()) {
                    %funcObj%()
                    return true
                }
            }
            if !(funcObj ~= "i)^[a-z]:[\\/]") {
                if (funcObj ~= "^\w+\(\S*\)$") { ;运行function()
                    arr := StrSplit(substr(funcObj, 1, strlen(funcObj) - 1), "(")
                    (arr[2] == "") ? %arr[1]%() : %arr[1]%(arr[2])
                    return true
                } else if (funcObj ~= "^(\w+)\.(\w+)\((.*)\)$") { ;NOTE 运行 class.method(param1)
                    RegExMatch(funcObj, "^(\w+)\.(\w+)\((.*)\)$", &m)
                    (m[3] != "") ? %m[1]%.%m[2]%(m[3]) : %m[1]%.%m[2]%()
                    return true
                }
                if (funcObj ~= '^\{\w{8}(-\w{4}){3}-\w{12}\}$') { ;clsid
                    funcObj := "explorer.exe shell:::" . funcObj
                } else if (funcObj ~= '^\w+\.cpl(,@?\d?)*$') { ;cpl
                    funcObj := "control.exe " . funcObj
                    ;} else if (substr(funcObj,1,12) == "ms-settings:") {
                    ;    funcObj := funcObj
                    ;} else if (funcObj ~= 'i)^control(\.exe)?\s+\w+\.cpl$') {
                    ;    funcObj := funcObj
                }
                tooltip(funcObj)
                run(funcObj)
                SetTimer(tooltip, -1000)
                return true
            }
            if (errExit)
                exit
            else
                throw OSError("action not find")
        }

        ;TODO 是否设置全局，这样出提示后，在其他未定义软件界面按键也能退出
        doGlobal_Escape() {
            OutputDebug(format("d#{1} {2}:A_ThisFunc={3} index={4}", A_LineFile, A_LineNumber, A_ThisFunc, this.index))
            if (this.index == 0) {
                if (this.HasOwnProp("funCheckEscape") && this.funCheckEscape.call()) {
                    OutputDebug(format("d#{1} {2}:funCheckEscape=true", A_LineFile, A_LineNumber))
                    send("{escape}")
                } else {
                    OutputDebug(format("d#{1} {2}:to mode1", A_LineFile, A_LineNumber))
                    this.win.SwitchMode(1)
                }
                ;} else if (this.index > 0 && this.win.arrModes.length > 2) { ;TODO 更多模式，还是热键兼容问题
                ;    n := this.index + 1
                ;    if (n == this.win.arrModes.length)
                ;        n := 1
                ;    this.win.SwitchMode(n)
            } else if (!this.arrKeyPressed.length && !this.win.count) {
                send("{escape}")
            } else {
                OutputDebug(format("i#{1} {2}: skipRepeat", A_LineFile, A_LineNumber))
                this.win.skipRepeat := true
            }
        }

        ;删除最后一个字符
        doGlobal_BackSpace() {
            this.win.skipRepeat := true
            if (this.arrKeyPressed.length) {
                OutputDebug(format("i#{1} {2}:UpdateState", A_LineFile, A_LineNumber))
                this.UpdateState()
            } else if (this.win.count) {
                OutputDebug(format("i#{1} {2}:HandleCount", A_LineFile, A_LineNumber))
                this.HandleCount("{BackSpace}")
            } else {
                send("{BackSpace}")
            }
        }
        ; doGlobal_Edit() {
        ;     SplitPath(A_LineFile, , &dn)
        ;     if (this.win.HasOwnProp("funEditSearch")) { ;TODO 增加方法来传入定位信息
        ;         sSearch := this.win.funEditSearch()
        ;         OutputDebug(format("i#{1} {2}:title={3}", A_LineFile, A_LineNumber, sSearch))
        ;         _c.e(format("{1}\wins\{2}\VimD_{2}.ahk", dn, this.win.name), sSearch)
        ;     } else {
        ;         OutputDebug(format("i#{1} {2}", A_LineFile, A_LineNumber))
        ;         _c.e(format("{1}\wins\{2}\VimD_{2}.ahk", dn, this.win.name))
        ;     }
        ; }
        doGlobal_Repeat() {
            this.win.isRepeat := true
            if (this.win.count)
                this.win.lastAction[2] := this.win.GetCount() ;覆盖 lastAction 的count
            OutputDebug(format("i#{1} {2}:Exec repeat={3} cnt={4}", A_LineFile, A_LineNumber, this.win.lastAction[3],
                this.win.lastAction[2]))
            this.Exec(this.win.lastAction*)
            this.win.isRepeat := false
        }
        doGlobal_Up() => send("{up}")
        doGlobal_Down() => send("{down}")
        doGlobal_Left() => send("{left}")
        doGlobal_Right() => send("{right}")
        doGlobal_objKeysmap() {
            ;msgbox(this.name . "`n" . this.index)
            res := ""
            for keymap, action in this.actions
                res .= format("{1}`t{2}`t{3}`t{4}`n", keymap, action["hotwin"], action["string"], action["comment"])
            msgbox(res, , 0x40000)
        }
        doGlobal_objFKey(key := "") {
            arr2 := []
            ;尝试获取key
            if (key == "") {
                oInput := inputbox("首键")
                if (oInput.result != "Cancel" && oInput.value != "")
                    key := oInput.value
            }
            if (key == "") {
                for _, obj in this.leaderKey2ActionMap
                    getStr(obj, _)
            } else {
                getStr(this.leaderKey2ActionMap[key], key)
            }
            hyf_GuiListView(arr2, ["标题", "模式", "首键", "所有键", "描述", "其他"
            ])
            getStr(obj, k0 := "") {
                for tp in ["dynamic", "normal"
                ] {
                    if (!obj.has(tp))
                        continue
                    for action in obj[tp] {
                        arr2.push([action["hotwin"], tp, k0, action["string"], action["comment"]
                        ])
                        if (action["groupLevel"])
                            arr2[-1].push(action.get(VimD.groupKeymap, "group"))
                    }
                }
            }
        }
        doGlobal_Debug_objSingleKey() {
            res := ""
            for winTitle, obj in this.win.objRegisteredHotkeys {
                for k, arr in obj
                    res .= format("{1}:{2}`n", winTitle, k)
            }
            msgbox(res, , 0x40000)
        }
        doGlobal_Debug_objKeySuperVim() {
            res := ""
            for k, arr in this.win.superKeys
                res .= format("{1}`n", k)
            msgbox(res, , 0x40000)
        }
        doGlobal_Debug_objFunDynamic() {
            res := ""
            for k, arr in this.objDynamicHandlers
                res .= format("{1}`n", k)
            msgbox(res, , 0x40000)
        }
        doGlobal_Debug_arrHistory() {
            res := ""
            for arr in this.win.arrActionHistory
                res .= format("{1}, {2}`n", arr[3], arr[2])
            msgbox(res, , 0x40000)
        }

        ;-----------------------------------tip-----------------------------------

        ;添加动态提示内容
        AddDynamicTip(str := "") {
            if (str == "") {
                if (this.arrDynamicTips.length)
                    this.arrDynamicTips.pop()
            } else {
                if (!this.arrDynamicTips.length)
                    this.arrDynamicTips.push(str)
                else if (this.arrDynamicTips[-1] != str) ;如果按 BackSpace 会造成重复添加
                    this.arrDynamicTips.push(str)
            }
        }

        ShowTips(arrMatch) {
            if (VimD.debugLevel > 0)
                OutputDebug(format("i#{1} {2}:{3} this.sKeyPressed={4}", A_LineFile, A_LineNumber, A_ThisFunc, this.sKeyPressed
                ))
            strTooltip := this.objTips.has(this.sKeyPressed)
                ? format("{1}`t{2}", this.sKeyPressed, this.objTips[this.sKeyPressed])
                : this.sKeyPressed
            for s in this.arrDynamicTips
                strTooltip .= "`t" . s ;NOTE 添加动态信息
            strTooltip .= "`n=====================`n"
            key := VimD.groupStatus ? VimD.groupKeymap : "string"
            for action in arrMatch
                strTooltip .= format("{1}`t{2}`n", RegExReplace(action[key], "\s|\{space\}", "☐"), action["comment"]) ;NOTE 空格需要转换
            this._ShowTip(strTooltip)
        }

        ;NOTE
        _ShowTip(str) {
            ;OutputDebug(format("i#{1} {2}:isobject={3} _ShowTip str={4}", A_LineFile,A_LineNumber,isobject(this.win.skipRepeat),str))
            if (isobject(this.win.skipRepeat)) {
                cmToolTip := A_CoordModeToolTip
                CoordMode("ToolTip", "window") ;强制为 window 模式
                arrXY := this.win.skipRepeat.call()
                ;OutputDebug(format("i#{1} {2}:arrXY={3}", A_LineFile,A_LineNumber,json.stringify(arrXY)))
                tooltip(str, arrXY[1], arrXY[2], VimD.tipLevel)
                ;OutputDebug(format("i#{1} {2}:after tooltip", A_LineFile,A_LineNumber))
                CoordMode("ToolTip", cmToolTip)
            } else {
                MouseGetPos(&x, &y)
                x += 20 * A_ScreenDPI // 96 ;NOTE 防止鼠标挡住
                y += 20 * A_ScreenDPI // 96
                tooltip(str, x, y, VimD.tipLevel)
            }
        }

    }

}

;OnError(ErrorHandler)
;ErrorHandler(exception, mode) {
;    msgbox(exception.file . "`n" . exception.line,,0x40000)
;    VimD.ErrorHandler() ;NOTE 否则 VimD 下个按键会无效
;}

#include VimDInclude.ahk
