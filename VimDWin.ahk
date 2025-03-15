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
        this.currentMode := VimDMode(idx, this, modename) ;modename 用来修改内置模式名
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
