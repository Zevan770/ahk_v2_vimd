#Requires AutoHotkey v2.0-beta
#SingleInstance Force
#warn Unreachable, off
#MapCaseSense off
SetControlDelay(-1)
SetKeyDelay(-1)
CoordMode("mouse", "window")
CoordMode("tooltip", "window")
CoordMode("pixel", "window")
CoordMode("caret", "window")
CoordMode("menu", "window")

;@Ahk2Exe-SetProductVersion %A_AhkVersion%hy

A_UserProfile := EnvGet("USERPROFILE")
A_LocalAppdata := EnvGet("LOCALAPPDATA")
;TODO 添加 A_LineDir

;map 可用.访问属性(OA首页按F4出错)
;map.prototype.DefineProp('__get', {call: (self, key, *) => self[key]})
;map.prototype.DefineProp('__set', {call: (self, key, params, value) => self[key] := value})

;@Ahk2Exe-IgnoreBegin
;@Ahk2Exe-Obey U_bits, = %A_PtrSize% * 8
;@Ahk2Exe-Obey U_type, = "%A_IsUnicode%" ? "Unicode" : "ANSI"
;@Ahk2Exe-ExeName %A_ScriptName~\.[^\.]+$%_%U_type%_%U_bits%
;@Ahk2Exe-Let vvvv = "v"
CodeVersion := "1.2.3.4"
;@Ahk2Exe-Let U_version = %A_PriorLine~U)^(.+"){1}(.+)".*$~$2%
company := "My Company"
;@Ahk2Exe-Let U_company = %A_PriorLine~U)^(.+"){3}(.+)".*$~$2%
;@Ahk2Exe-IgnoreEnd

;#include <JSON>
;#include <struct>

#include <Class_String>
#include <Class_Number>
#include <Class_Array>
#include <Class_Map>
#include <Class_Date>
#include <Class_Timer>
#include <Yaml>
#include <WinHttpRequest>
#include <Class_Gui>
#include <LVICE_XXS>
#include <WatchFolder>

#include <Socket>
#include <Class_CDP>
#include <Class_Clipboard>
#include <CentBrowser>
#include <msedge>
#include <Class_Pinyin>
#include <hyaray>
#include <Class_XYXY>
#include <Class_Mouse>
#include <Class_Ctrl>
#include <Class_UIA>
#include <Class_Gdip>

#include <Explorer>