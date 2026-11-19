#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
; 检查间隔，单位：分钟
; 默认每 60 分钟打开一次
; ============================================================
N := 30

Url1 := "https://www.maoyan.com/cinema/12261?poi=5874436&movieId=1545360"
Url2 := "https://www.maoyan.com/cinema/41053?poi=1832463100&movieId=1545360"

; 脚本启动后立即打开一次
OpenPages()

; 此后每 N 分钟打开一次
SetTimer(OpenPages, N * 60 * 1000)


OpenPages() {
    global Url1, Url2

    Run(Url1)
;   Run(Url2)
}
