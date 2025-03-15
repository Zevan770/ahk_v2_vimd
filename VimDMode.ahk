;TODO mode暂时不支持子窗口
;-----------------------------------maps-----------------------------------
;-----------------------------------do__-----------------------------------
;-----------------------------------tip-----------------------------------
class VimDMode {
    /** @type {VimDWin} */
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
            if (this.arrKeyPressed.length && this.leaderKey2ActionMap.has(this.arrKeyPressed[1])
            && this.leaderKey2ActionMap[this.arrKeyPressed[1]].has("group")) {
                this.leaderKey2ActionMap[this.arrKeyPressed[1]].delete("group")
            }
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
                VimD.logger.debug(format("i#{1} {2}:{3} is superKey", A_LineFile, A_LineNumber, A_ThisFunc))
                exit
            } else if (checkSuper && this.win.superKeys.has(keyMap)) { ;<super>
                VimD.logger.debug(format("i#{1} {2}:{3} {4} is <super>", A_LineFile, A_LineNumber, A_ThisFunc, keyMap
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
                    VimD.logger.debug(format("i#{1} {2}:{3} keyMap={4} onBeforeKey false", A_LineFile, A_LineNumber,
                        A_ThisFunc, keyMap))
                    send(VimD.Map2Send(keyMap))
                    exit
                }
            }
            ;if (this.win.superModeType == 2) ;<super>键显示保存的模式名
            ;    this.AddDynamicTip(this.win.modeBeforeSuper.name)
            ;自动运行 objDynamicHandlers()
            if (this.HasOwnProp("objDynamicHandlers") && this.objDynamicHandlers.has(keyMap)) {
                VimD.logger.debug(format("i#{1} {2}:{3} {4}.objDynamicHandlers({5})", A_LineFile, A_LineNumber,
                    A_ThisFunc,
                    this.name, keyMap))
                if (this.leaderKey2ActionMap.has(keyMap))
                    this.leaderKey2ActionMap[keyMap]["dynamic"] := [] ;NOTE 每次都要清空
                if (this.objDynamicHandlers[keyMap]()) { ;TODO 特意有返回值的，表示已执行完动作，直接结束 <2023-01-20 22:25:39> hyaray
                    this.init()
                    exit
                }
                ;OutputDebug(format("i#{1} {2}:{3} dynamic={4}", A_LineFile,A_LineNumber,A_ThisFunc,json.stringify(this.leaderKey2ActionMap[keyMap]["dynamic"],4)))
            } else {
                VimD.logger.debug(format("i#{1} {2}:{3} 键没有动态", A_LineFile, A_LineNumber, keyMap))
            }
            ;非常规功能
            if (this.actions.has(keyMap)) { ;单键功能
                VimD.logger.debug(format("i#{1} {2}:this.actions.has({3}) comment={4}", A_LineFile, A_LineNumber,
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
                VimD.logger.debug(format("d#{1} {2}:this.actions.not has({3}) index={4}", A_LineFile, A_LineNumber,
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
                VimD.logger.debug(format("i#{1} {2}:{3} no key", A_LineFile, A_LineNumber, A_ThisFunc))
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
                    VimD.logger.debug(format("i#{1} {2}:{3} send({4})", A_LineFile, A_LineNumber, A_ThisFunc, this.arrKeyPressed[
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
                VimD.logger.debug(format("i#{1} {2}:{3} 1 matched={4}", A_LineFile, A_LineNumber, A_ThisFunc,
                    arrMatch[1]["comment"]))
                this.init(-1)
                this.Exec(arrMatch[1]["action"], this.win.GetCount(), arrMatch[1]["comment"])
                this.init(1)
            default: ;大部分情况
                this.ShowTips(arrMatch)
        }
        ;所有匹配热键(dynamic+normal)
        getMatchAction() {
            VimD.logger.debug(format("i#{1} {2}:{3}", A_LineFile, A_LineNumber, A_ThisFunc))
            ;按键未定义功能
            if (!this.leaderKey2ActionMap.has(this.arrKeyPressed[1])) {
                VimD.logger.debug(format("i#{1} {2}:{3} first key not matched", A_LineFile, A_LineNumber, A_ThisFunc))
                return []
            }
            ;常规情况
            if (!this.leaderKey2ActionMap[this.arrKeyPressed[1]].has("group")) {
                VimD.logger.debug(format("i#{1} {2}:{3} first key no group", A_LineFile, A_LineNumber, A_ThisFunc))
                return _matchAction()
            }
            ;NOTE group 情况
            switch this.arrKeyPressed.length {
                case 1: ;首个按键，只显示分组功能
                    arrMatch := _matchAction(1)
                    if (arrMatch.length == 1) { ;只有1组，则直接展开下级
                        VimD.logger.debug(format("i#{1} {2}:{3} only 1 group, groupStatus", A_LineFile, A_LineNumber,
                            A_ThisFunc))
                        arrMatch := groupLoadGlobal(true)
                    }
                case 2: ;第2按键
                    if (VimD.groupStatus) { ;已经展开了全局
                        arrMatch := groupLoadGlobal()
                    } else { ;搜索分组
                        arrMatch := _matchAction(2)
                        if (!arrMatch.length) { ;TODO 找不到分组，搜索全部分组下的节点
                            VimD.logger.debug(format("i#{1} {2}:{3} group not matched", A_LineFile, A_LineNumber,
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
            VimD.logger.debug(format("i#{1} {2}:{3} arrMatch={4}", A_LineFile, A_LineNumber, A_ThisFunc, json.stringify(
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
                VimD.logger.debug(format("i#{1} {2}:{3} this.sKeyPressed={4} key={5}", A_LineFile, A_LineNumber,
                    A_ThisFunc, this.sKeyPressed, key))
                for tp in ["dynamic", "normal"
                ] {
                    if (!this.leaderKey2ActionMap[this.arrKeyPressed[1]].has(tp))
                        continue
                    VimD.logger.debug(format("i#{1} {2}:{3} tp={4} {5}", A_LineFile, A_LineNumber, A_ThisFunc, tp,
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
                VimD.logger.debug(format("i#{1} {2}:{3} arrMatch={4}", A_LineFile, A_LineNumber, A_ThisFunc, json.stringify(
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
            VimD.logger.debug(format("i#{1} {2}:{3} arrKeyPressed={4}", A_LineFile, A_LineNumber, A_ThisFunc, json
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
        VimD.logger.debug(format("d#{1} {2}:{3} count={4}", A_LineFile, A_LineNumber, A_ThisFunc, cnt))
        ;NOTE 运行
        loop (cnt) {
            this.ExecAction(varDo, true)
            if (this.win.skipRepeat) { ;运行后才知道是否 skipRepeat
                VimD.logger.debug(format("d#{1} {2}:break", A_LineFile, A_LineNumber))
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
        VimD.logger.debug(format("i#{1} {2}:{3} this.sKeyPressed={4}", A_LineFile, A_LineNumber, A_ThisFunc, this.sKeyPressed
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
