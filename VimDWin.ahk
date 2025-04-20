;窗口对象会直接生成两个默认的mode(changeMode获取)
;模式由各插件自行定义(生成+map一并进行)
class VimDWin {
    ;主要属性
    /** @type {String} */
    name := ""

    /** @type {String} */
    winTitle := ""

    /** @type {String} */
    noWinTitle := ""

    /**
     * 也可以理解为id 到 mode的映射
     * @type {Array<VimDMode>} 
     */
    arrModes := []

    /** @type {VimDMode} */
    curMode := ""

    /** @type {Array} */
    registeredHotkeys := []

    /** @type {Integer} */
    count := 0

    /** @type {Integer} */
    maxCount := 100

    /** @type {Boolean} */
    isRepeating := false

    /** @type {String} */
    keyToMode0 := "f2"

    /** @type {String} */
    keyToMode1 := "Escape"

    /** @type {VimDAction} */
    lastAction := ""

    /** @type {Integer} */
    lastCount := 0

    ;事件属性
    /** @type {Function} */
    onBeforeChangeMode := ""

    /** @type {Function} */
    onAfterChangeMode := ""

    /** @type {Function} */
    onBeforeShowTip := ""

    /** @type {Function} */
    onBeforeHideTip := ""

    __new(name) {
        this.name := name
    }

    /**
     * 初始化内置的模式(mode0|mode1)
     * 此方法由各插件调用(生成+map一并进行)
     * 默认的模式放最后定义，或者最后加上 win.SwitchMode(i)
     * NOTE 必须先 SetHotIf
     * @param opt 二进制0位代表mapRepeat, 1位代表mapCount
     */
    InitMode(idx, onBeforeKey := false, modename := "", opt := 3) {
        if (idx == 1 && this.arrModes.length == 0)
            this.InitMode(0)
        this.curMode := VimDMode(idx, this, modename) ;modename 用来修改内置模式名
        if (this.arrModes.length < idx + 1)
            this.arrModes.push(this.curMode)
        else
            this.arrModes[idx + 1] := this.curMode

        this.curMode.MapDefault(opt)
        if (onBeforeKey)
            this.curMode.onBeforeKey := isobject(onBeforeKey) ? onBeforeKey : ObjBindMethod(this.curMode,
                "BeforeKey")
        return this.curMode
    }

    GetMode(i := unset) {
        if (!IsSet(i))
            return this.curMode
        else
            return this.arrModes[i + 1]
    }

    SetMode(i) => this.curMode := this.GetMode(i)

    GetCount(cntDefault := 1) {
        return this.count ? Min(this.count, this.maxCount) : cntDefault
    }

    ;设置curMode，不存在会自动new
    ;由于会触发事件，所以不能在初始化时使用，很可能找不到窗口出错
    ;i 从0开始
    SwitchMode(i) {
        if (this.onBeforeChangeMode)
            this.onBeforeChangeMode.call(this.curMode)
        tooltip(this.SetMode(i).name)
        SetTimer(tooltip, -1000)
        if (this.onAfterChangeMode) ;TODO 一般用来修改样式让用户清楚当前在哪个模式
            this.onAfterChangeMode.call(this.curMode)
        return this.curMode
    }

    ;NOTE 由 VimDWin 对象接收按键并调度
    ;这里只处理特殊情况
    ;由 _keyIn() 处理后续细节
    ;byScript 非手工按键，而是用脚本触发时，需要传入此参数，如 VimD_WeChat.win.keyIn("F3", "ahk_exe WeChat.exe")
    keyIn(ThisHotkey, byScript := 0) {

        ;VimD.logger.debug(format("i#{1} {2}:A_ThisFunc={3}-------------------start", A_LineFile,A_LineNumber,A_ThisFunc))
        ;VimD.logger.debug(format("curMode.index={1}", this.curMode.index))
        ;VimD.logger.debug(format("keySeq.length = {1}", this.curMode.keySeq.length))
        ;VimD.logger.debug(format("keyMap={1}", keyMap))
        ;VimD.logger.debug(format("i#{1} {2}:A_ThisFunc={3}-------------------end", A_LineFile,A_LineNumber,A_ThisFunc))
        ;NOTE 记录当前的窗口，用来出错后 init
        VimD.curWin := this
        this.curMode._keyIn(ThisHotkey, byScript)
        if (this.curMode.onAfterKey)
            this.curMode.onAfterKey.call(ThisHotkey)
    }

    Active() {
        if (WinActive(this.winTitle, , this.noWinTitle)) {
            return true
        } else {
            VimD.logger.debug(format("winTitle={1}, noWinTitle={2} not active", this.winTitle, this.noWinTitle))
            return false
        }
    }

}
