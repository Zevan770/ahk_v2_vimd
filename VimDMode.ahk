class VimDMode {
    /** @type {VimDWin} */
    win := unset

    /** @type {Map<String, VimDAction>} */
    actions := Map()

    /** @type {VimDAction} */
    tmpAction := ""

    /** @type {Map<String, String>} */
    objTips := Map()

    /** @type {VimDkeySequence} */
    keySeq := VimDkeySequence()

    /** @type {Func} */
    onBeforeKey := ""

    /** @type {String} */
    onAfterKey := ""

    /** @type {String} */
    onBeforeDo := ""

    /** @type {String} */
    onAfterDo := ""

    __new(idx, win, modename := "") {
        this.index := idx
        this.win := win ;标记是哪个窗口的mode
        if (idx > 1)
            VimD.arrModeName.push(modename != "" ? modename : format("mode{1}", idx))
        else if (modename != "") ;修改内置模式名
            VimD.arrModeName[this.index + 1] := modename
        this.name := this.win.name . "-" . VimD.arrModeName[this.index + 1]
        this.objTips.CaseSense := true
        this.actions.CaseSense := true
    }

    ;脚本运行过程出错，要先运行此命令退出，否则下次按键会因为 keySeq 误判(往往使下一按键无效)
    ;NOTE 执行命令或中途退出才执行
    ;type -1=执行前半段 0=全部执行 1=执行后半段
    init(type := 0) {
        ;VimD.logger.debug(format("i#{1} {2}:init tp={3} start", A_LineFile,A_LineNumber,tp))
        if (type <= 0) { ;用于在do之前先初始化一部分
            this.keySeq.keys := []
            VimD.HideTips1()
            VimD.HideTips()
        }
        if (type >= 0) { ;影响执行逻辑的属性
            this.win.count := 0
            this.win.isRepeating := false
            this.win.skipRepeat := false
        }
    }

    ;NOTE 被keyIn调用
    _keyIn(thisHotkey, byScript) {
        ;第一个按键
        if (this.handleSpecialKey(thisHotkey)) {
            exit
        }

        this.keySeq.AddKey(thisHotkey)

        if (!this.actions.Has(this.keySeq.ToString())) {
            this.init()
            exit
        }

        this.tmpAction := this.actions[this.keySeq.ToString()]
        if (this.tmpAction.rhs != "") {
            this.Exec(this.tmpAction.rhs, this.win.GetCount(), this.tmpAction.desc)
            this.init()
        } else {
            ; TODO showtips
        }

    }

    HandleSpecialKey(thisHotkey) {
        if (!this.actions.has(thisHotkey)) {
            return false
        }
        if (thisHotkey ~= "^\d$") {
            this.HandleCount(integer(thisHotkey)) ;因为要传入参数，所以单独处理
            return true
        } else if (thisHotkey == "{BackSpace}") {
            this.GlobalActionBS() ;因为无需 init，所以单独处理
            return true
        } else if (thisHotkey == ".") {
            this.init(-1)
            this.GlobalActionRepeat() ;一般是 Exec(action.rhs, this.win.GetCount())，repeat 刚好相反
            this.init(1)
            return true
        } else {
            return false
        }
    }

    HandleCount(keyMap) {
        if (keyMap == "{BackSpace}") {
            if (this.win.count > 9) { ;两位数
                this.win.count := this.win.count // 10
                VimD.logger.debug(format("i#{1} {2}:this.win.count={3}", A_LineFile, A_LineNumber, this.win.count))
            } else {
                this.init()
                return
            }
        } else {
            this.win.count := this.win.count ? this.win.count * 10 + integer(keyMap) : integer(keyMap)
        }
        this._ShowTip(string(this.win.count))
    }

    ;-----------------------------------maps-----------------------------------

    MapDefault(opt) {
        if (this.index == 0) { ;mode0
            if (this.win.keyToMode1 != "") {
                EscapeCondition(mode, thisHotkey) {
                    return !(mode.win.count == 0 && mode.keySeq.keys.length == 0)
                }
                this.MapKey(this.win.keyToMode1, ObjBindMethod(this, "GlobalActionEscape"), "进入 mode1", EscapeCondition
                .Bind(this))
            }
        } else if (this.index == 1) { ;mode1
            ; this.MapKey("escape", ObjBindMethod(this, "GlobalActionEscape"), "escape")
            ; this.MapKey("BackSpace", ObjBindMethod(this, "GlobalActionBS"), "BackSpace")

            if (this.win.keyToMode0 != "")
                this.MapKey(this.win.keyToMode0, ObjBindMethod(this.win, "SwitchMode", 0), "进入 mode0")
            ; ;NOTE 定义debug的内置功能，自带 <super> 参数
            ; this.MapKey(format("<super>{1}{1}", this.win.keyDebug), ObjBindMethod(this, "GlobalActionEdit"),
            ; "【编辑】VimD_" . this.win.name)
            ; this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "d"), ObjBindMethod(VimD.logger, "SetDebugLevel"),
            ; "显示/隐藏调试信息")
            ; this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "["), ObjBindMethod(this, "GlobalActionobjFKey"),
            ; "查看所有功能(按首键分组)leaderKey2ActionMap")
            ; this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "]"), ObjBindMethod(this, "GlobalActionobjKeysmap"),
            ; "查看所有功能(按keymap分组)actions")
            ; this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "k"), ObjBindMethod(this,
            ;     "GlobalActionDebug_objSingleKey"), "查看所有拦截的按键 registeredHotkeys")
            ; this.MapKey(format("<super>{1}{2}", this.win.keyDebug, "/"), ObjBindMethod(this,
            ;     "GlobalActionDebug_arrHistory"), "查看运行历史 arrActionHistory")
            n := 0 ;二进制的位数<super>(从右开始)
            if ((opt & 2 ** n) >> n) ;也可以用 "10" 这种字符串来判断
                this.MapCount()
            n++
            if ((opt & 2 ** n) >> n)
                this.MapKey(".", "", "重做")
        }
    }

    MapCount() {
        loop (10)
            this.MapKey(string(A_Index - 1), "", format("<{1}>", A_Index - 1))
    }

    /**
     * @description 映射按键
     * @param {String} lhs
     * @param {String|Func} rhs
     * @param {String} desc
     * @param {Func} condition
     */
    MapKey(lhs, rhs := unset, desc := unset, condition := unset) {
        this._Map(lhs, rhs?, desc?, condition?, "normal")
    }

    /**
     * @description 把定义打包为 action
     * @param {String} lhs
     * @param {String|Func} rhs
     * @param {String} desc
     * @param {Func} condition
     */
    _Map(lhs, rhs := unset, desc := unset, condition := unset, type := "normal") {
        /** @type  {VimDkeySequence} */
        keySeq := VimDkeySequence.Lhs2KeySeq(lhs)
        /** @type {VimDAction} */
        action := VimDAction()
        action.keySeq := keySeq
        action.rhs := rhs
        action.desc := IsSet(desc) ? desc : rhs
        action.type := type
        action.mode := this

        leaderKeys := keySeq.GetLeaderKeys()
        if (!this.actions.has(leaderKeys.ToString()) && leaderKeys.keys.length) {
            this._Map(leaderKeys.ToString(), "", "", , "normal")
        }

        for key in action.keySeq.keys {
            if (!this.win.registeredHotkeys.has(key)) { ;单键避免重复定义
                HotIf(ObjBindMethod(this, "HotIfCondition", , condition?))
                Hotkey(key, ObjBindMethod(this.win, "keyIn")) ;NOTE 相关的键全部拦截，用 VimD 控制
                this.win.registeredHotkeys.Push(key)
            }
        }
        this.actions[keySeq.ToString()] := action
    }

    ;-----------------------------------do__-----------------------------------
    BeforeKey(p*) => !CaretGetPos() ;有些软件要用 UIA.GetFocusedElement().CurrentControlType != UIA.ControlType.Edit

    ;最终执行的命令
    ;因为 GlobalActionRepeat 调用，所以把 cnt 放参数
    ;为什么第一个参数不用 action
    Exec(rhs, count, comment := "") {
        ;处理 repeat 和 count
        if (!this.win.isRepeating) {
            this.win.lastAction := this.tmpAction
            this.win.lastCount := count
            ; TODO history
        }
        ;NOTE 运行
        loop (count) {
            this.ExecFunc(rhs, true)
        }
        if (isobject(this.onAfterDo))
            this.ExecFunc(this.onAfterDo)
    }

    ExecFunc(rhs, errExit := false) {
        if !(rhs is string) {
            rhs()
            return true
        }
        try {
            if (type(%rhs%).isFunc()) {
                %rhs%()
                return true
            }
        }
        if !(rhs ~= "i)^[a-z]:[\\/]") {
            if (rhs ~= "^\w+\(\S*\)$") { ;运行function()
                arr := StrSplit(substr(rhs, 1, strlen(rhs) - 1), "(")
                (arr[2] == "") ? %arr[1]%() : %arr[1]%(arr[2])
                return true
            } else if (rhs ~= "^(\w+)\.(\w+)\((.*)\)$") { ;NOTE 运行 class.method(param1)
                RegExMatch(rhs, "^(\w+)\.(\w+)\((.*)\)$", &m)
                (m[3] != "") ? %m[1]%.%m[2]%(m[3]) : %m[1]%.%m[2]%()
                return true
            }
            if (rhs ~= '^\{\w{8}(-\w{4}){3}-\w{12}\}$') { ;clsid
                rhs := "explorer.exe shell:::" . rhs
            } else if (rhs ~= '^\w+\.cpl(,@?\d?)*$') { ;cpl
                rhs := "control.exe " . rhs
                ;} else if (substr(funcObj,1,12) == "ms-settings:") {
                ;    funcObj := funcObj
                ;} else if (funcObj ~= 'i)^control(\.exe)?\s+\w+\.cpl$') {
                ;    funcObj := funcObj
            }
            tooltip(rhs)
            run(rhs)
            SetTimer(tooltip, -1000)
            return true
        }
        if (errExit)
            exit
        else
            throw OSError("action not find")
    }

    GlobalActionEscape() {
        if (this.index == 0) {
            this.win.SwitchMode(1)
        } else {
            this.win.skipRepeat := true
        }
    }

    ;删除最后一个字符
    GlobalActionBS() {
        ; this.win.skipRepeat := true
        ; if (this.keySeq.length) {
        ;     this.HandleMultiKey()
        ; } else if (this.win.count) {
        ;     this.HandleCount("{BackSpace}")
        ; }
        ;TODO
    }
    ; GlobalActionEdit() {
    ;     SplitPath(A_LineFile, , &dn)
    ;     if (this.win.HasOwnProp("funEditSearch")) { ;TODO 增加方法来传入定位信息
    ;         sSearch := this.win.funEditSearch()
    ;         VimD.logger.debug(format("i#{1} {2}:title={3}", A_LineFile, A_LineNumber, sSearch))
    ;         _c.e(format("{1}\wins\{2}\VimD_{2}.ahk", dn, this.win.name), sSearch)
    ;     } else {
    ;         VimD.logger.debug(format("i#{1} {2}", A_LineFile, A_LineNumber))
    ;         _c.e(format("{1}\wins\{2}\VimD_{2}.ahk", dn, this.win.name))
    ;     }
    ; }
    GlobalActionRepeat() {
        this.win.isRepeating := true
        this.Exec(this.win.lastAction.rhs, this.win.lastCount)
        this.win.isRepeating := false
    }
    GlobalActionobjKeysMap() {
        ;msgbox(this.name . "`n" . this.index)
        res := ""
        for keySeq, action in this.actions
            res .= format("{1}`t{2}`t{3}`t{4}`n", keySeq, action.mode.win, action.desc)
        msgbox(res, , 0x40000)
    }
    GlobalActionobjFKey(key := "") {
        ; arr2 := []
        ; ;尝试获取key
        ; if (key == "") {
        ;     oInput := inputbox("首键")
        ;     if (oInput.result != "Cancel" && oInput.value != "")
        ;         key := oInput.value
        ; }
        ; if (key == "") {
        ;     for _, obj in this.leaderKey2ActionMap
        ;         getStr(obj, _)
        ; } else {
        ;     getStr(this.leaderKey2ActionMap[key], key)
        ; }
        ; hyf_GuiListView(arr2, ["标题", "模式", "首键", "所有键", "描述", "其他"
        ; ])
        ; getStr(obj, k0 := "") {
        ;     for type in ["dynamic", "normal"
        ;     ] {
        ;         if (!obj.has(tp))
        ;             continue
        ;         for action in obj[tp] {
        ;             arr2.push([action["hotwin"], tp, k0, action["string"], action.desc
        ;             ])
        ;         }
        ;     }
        ; }
    }
    GlobalActionDebug_objSingleKey() {
        res := ""
        for winTitle, obj in this.win.registeredHotkeys {
            for k, arr in obj
                res .= format("{1}:{2}`n", winTitle, k)
        }
        msgbox(res, , 0x40000)
    }
    GlobalActionDebug_arrHistory() {
        res := ""
        for arr in this.win.arrActionHistory
            res .= format("{1}, {2}`n", arr[3], arr[2])
        msgbox(res, , 0x40000)
    }

    ;-----------------------------------tip-----------------------------------

    ShowTips(arrMatch) {
        ; strTooltip := this.objTips.has(this.sKeySeq)
        ;     ? format("{1}`t{2}", this.sKeySeq, this.objTips[this.sKeySeq])
        ;     : this.sKeySeq
        ; for s in this.arrDynamicTips
        ;     strTooltip .= "`t" . s ;NOTE 添加动态信息
        ; strTooltip .= "`n=====================`n"
        ; key := VimD.groupStatus ? VimD.groupKeymap : "string"
        ; for action in arrMatch
        ;     strTooltip .= format("{1}`t{2}`n", RegExReplace(action[key], "\s|\{space\}", "☐"), action.desc) ;NOTE 空格需要转换
        ; this._ShowTip(strTooltip)
    }

    ;NOTE
    _ShowTip(str) {
        ;VimD.logger.debug(format("i#{1} {2}:isobject={3} _ShowTip str={4}", A_LineFile,A_LineNumber,isobject(this.win.skipRepeat),str))
        if (isobject(this.win.skipRepeat)) {
            cmToolTip := A_CoordModeToolTip
            CoordMode("ToolTip", "window") ;强制为 window 模式
            arrXY := this.win.skipRepeat.call()
            ;VimD.logger.debug(format("i#{1} {2}:arrXY={3}", A_LineFile,A_LineNumber,json.stringify(arrXY)))
            tooltip(str, arrXY[1], arrXY[2], VimD.tipLevel)
            ;VimD.logger.debug(format("i#{1} {2}:after tooltip", A_LineFile,A_LineNumber))
            CoordMode("ToolTip", cmToolTip)
        } else {
            MouseGetPos(&x, &y)
            x += 20 * A_ScreenDPI // 96 ;NOTE 防止鼠标挡住
            y += 20 * A_ScreenDPI // 96
            tooltip(str, x, y, VimD.tipLevel)
        }
    }

    Active() {
        if (this.win.curMode.name != this.name) {
            return false
        }
        if (this.onBeforeKey != "") {
            if (!this.onBeforeKey.call()) {
                return false
            }
        }
        return true
    }

    HotIfCondition(thisHotkey, condition := unset) {
        if (this.win.Active() && this.Active()) {
            if (IsSet(condition) && Type(%condition%).isFunc()) {
                VimD.logger.debug(Format("{1},{2}", condition, thisHotkey))
                return condition.Call(thisHotkey)
            } else {
                return true
            }
        }
        VimD.logger.debug("HotIfCondition false")
        return false

    }
}

class VimDAction {
    /**
     * @description 模式 
     * @type {VimDMode} 
     */
    mode := ""

    /**
     * @type {String}
     */
    type := ""

    /**
     * 		
     * @description 
     * @type {VimDkeySequence} 
     */
    keySeq := []

    /**
     * @description 动作 
     * @type {String|Func} 
     */
    rhs := ""

    /**
     * @description 描述 
     * @type {String} 
     */
    desc := ""

    /**
     * @description 以此键开头的映射
     * @type {Map<String, VimDAction>}
     */
    mapping := Map()

    /**
     * @description 简短描述
     * @type {String}
     */

    shortDesc := ""

}

/**
 * @description 按键序列 
 * 按键的几种形态: 
 */
class VimDkeySequence {

    static SplitChar := " "
    /**
     * @description 按键序列 
     * @type {Array<String>} 
     */
    keys := []

    __New(keys := []) {
        this.keys := keys
    }

    /**
     * @description 将给定的 lhs 转换为按键序列
     * @param {String} lhs
     */
    static Lhs2KeySeq(lhs) {
        strs := StrSplit(lhs, this.SplitChar)
        arr := []
        for _, str in strs {
            arr.Push(KeyUtil.Lhs2Hot(str))
        }
        return VimDkeySequence(arr)
    }

    ToString() {
        return this.keys.join(VimDkeySequence.SplitChar)
    }

    /**
     * @description 添加按键到序列
     * @param {String} key
     */
    AddKey(key) {
        this.keys.push(key)
    }

    GetLeaderKeys() {
        if (this.keys.length == 0) {
            return VimDkeySequence()
        }
        leaderKeys := this.keys.clone()
        leaderKeys.Pop()
        return VimDkeySequence(leaderKeys)
    }

    GetLastKey() {
        return this.keys[-1]
    }
}

class KeyUtil {
    /**
     * @description 将大写字母转换为小写字母前加 + 号
     * G -> +g
     */
    static Lhs2Hot(lhs) {
        if (lhs ~= "^[A-Z]$") {
            return "+" . StrLower(lhs)
        }
        return lhs
    }

    /**
     * 如果是+g，返回 G
     */
    static Hot2Visual(hot) {
        if (hot ~= "^\+[a-z]$") {
            return StrUpper(substr(hot, -1))
        }
        return hot
    }
}

class Utils {
    static icons := {
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
}
