/*
mapF11("{F11}")
mapF11(k0) {
    this.mode2.DefineGroup(k0) ;额外增加这句
    ;推荐简化版
    a := [
        ["分组a","a"],
        [
            ["注释axy","xy"],
            ["注释ayx","yx"],
        ]
    ]
    this.mode2.MapGroup(format("<super>{1}",k0), a)
    ;原始
    this.mode2.MapKey(format("<super>{1}{2}",k0,"b"),,"分组b", 1)
    this.mode2.MapKey(format("<super>{1}{2}",k0,"bxy"),msgbox.bind("bxy"),"注释bxy", 2)
    this.mode2.MapKey(format("<super>{1}{2}",k0,"bxz"),msgbox.bind("bxz"),"注释bxz", 2)
    this.mode2.MapKey(format("<super>{1}{2}",k0,"byx"),msgbox.bind("byx"),"注释byx", 2)
    this.mode2.MapKey(format("<super>{1}{2}",k0,"bz"),msgbox.bind("bz"),"注释bz", 2)
}
*/
