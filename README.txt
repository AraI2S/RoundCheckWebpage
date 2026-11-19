RoundCheckWebpage
版本：v2.0.0 | 2026-11-18
Windows 10 1703+ / Windows 11，使用系统自带 Windows PowerShell 5.1
绿色、开源、无需安装，不依赖 AutoHotkey，不需要打包 EXE，不需要管理员权限

一、用途和使用方法

RoundCheckWebpage 按设定的分钟周期，通过 Windows 默认浏览器打开一组网页。
启动后默认立即打开全部 URL 一次，之后按周期重复。默认设置来自原 AHK：30 分钟、一个启用的猫眼网址；原先被注释的第二个网址也保存在 Configuration.txt 中作为注释。

1. 解压完整文件夹；请勿直接在 ZIP 内运行文件。
2. 直接用记事本修改与 Main.cmd 同目录的 Configuration.txt。
3. 双击 Main.cmd。常驻主程序在后台运行，右下角任务栏托盘会出现图标；可能被收到「^」隐藏图标中。
4. 正常运行时不会留下 CMD / PowerShell / Windows Terminal 常驻窗口。Main.cmd 本身属于短暂的启动入口，启动瞬间可能闪现窗口。
5. 要停止，右键托盘图标，选择「退出 RoundCheckWebpage」。关闭已打开的浏览器页面不会退出定时器。

二、Configuration.txt 格式（最重要）

IntervalMinutes=30
OpenOnStart=true
https://example.com/
https://www.example.org/search?a=1&b=2

IntervalMinutes：周期分钟数，正整数 1—43200（最多 30 天），必填，只能出现一次。
OpenOnStart：可选，true 表示每次启动立即打开一轮；false 表示启动后先倒计时，默认 true。
每一行 http:// 或 https:// URL 就代表每轮打开一条网页。允许任意多个，没有 Url1、Url2、Enabled、数量上限或编号机制；按文件中从上到下的顺序逐个请求默认浏览器打开。若同一 URL 写了两次，会打开两次。
空行和以 #、; 开头的整行会被忽略。注释可用于临时禁用某条 URL。网址中包含 ?、&、=、# 等查询参数和片段均会完整保留（URL 行的行首不能是 #）。
未知配置字段、重复周期字段、周期超出范围、无有效 URL 或非法 URL 会报错，避免在错误配置下无声继续执行。
文件使用 UTF-8 编码，建议在 Windows 记事本中直接编辑和保存。

修改配置后，需要在托盘右键菜单选择「重新读取 Configuration.txt」；保存 TXT 本身不会立即生效。
重新读取时会一次性校验全部参数：成功后所有 URL、周期一起替换，并从重载时刻重新计时；不会因为重载而立刻打开网页；失败则保持此前有效配置和现有计时，弹出错误提示并写入 _Logs/error.log。
运行期间若外部删除 Configuration.txt，已加载的任务仍然执行；尝试重载时会提示文件缺失。关闭后再次启动则必须有有效配置。

三、托盘操作和计时语义

- 右键状态项：显示运行中/已暂停、周期分钟数、启用网址数量。
- 「立即打开全部网址」：按当前已加载的配置打开一轮。运行中手动打开后会重新开始下一轮倒计时；暂停期间仍可手动打开。
- 「暂停定时打开」：暂不自动打开网址。
- 「恢复定时打开」：从恢复时刻开始完整倒计时，不补开暂停期间的网页。
- 「重新读取 Configuration.txt」：安全重载。修改后的 URL 和周期一起生效；暂停状态原样保留。
- 「用记事本编辑 Configuration.txt」：使用系统 Notepad 打开文本，保存后需重新读取配置。
- 「退出 RoundCheckWebpage」：停止计时、隐藏托盘图标、释放资源。
- 双击托盘图标：相当于手动立即打开一轮。连续触发 2 秒冷却，避免重复点击不断新增标签页。

WinForms Timer 只负责每 500ms 查看一次是否到期；时间以 Stopwatch 的单调累计时间为基准。长时间睡眠/唤醒、机器繁忙或浏览器启动缓慢时不会“补发”错过的许多轮。定时器为非实时精度，实际执行可能略有延迟。
程序不会自动点击页面、刷新已有标签、购票、检测库存、抓取网页，也不会验证浏览器实际加载结果；每轮向默认浏览器分别提交全部 URL。
没有定义任何键盘热键，不安装键盘钩子，也不会模拟按键。

四、旧版迁移、单实例和备份

随包 Legacy/Round_Check_GT_Ticket.ahk 是最初的 AHK 原文件（原样保留）。
随包 Legacy/Round_Check_GT_Ticket_PS51_v1.0.0.zip 完整保留上一版程序（包含其 Config.ini 和 README），可自行回退。

旧版 v1.0.0 的 Config.ini 具有 IntervalMinutes、OpenOnStart、Url1Enabled、Url1、Url2Enabled、Url2 六个字段。
若需要导入旧版个人设置，可把旧 Config.ini 复制到新版 Main.cmd 同一目录，再将新版的 Configuration.txt 改名备份或移走。下一次启动如果找不到 Configuration.txt，但发现同目录的 Config.ini，将自动创建新的 Configuration.txt：
- 沿用原周期和 OpenOnStart。
- 把 Url1 和 Url2 转换为逐行 URL。
- 旧版 Enabled=false 的网址变成注释行（仍保留地址）。
- 老 Config.ini 原文件不修改。如果已存在 Configuration.txt，则始终以它为准，不会覆盖或自动合并。
完成导入后请检查 Configuration.txt 内容。此自动迁移仅识别上一版固定的六个字段。

同一目录的 v2 重复启动，使用 Mutex/EventWaitHandle 通知旧实例退出，最多等待 8 秒，然后由新进程接管，并根据 OpenOnStart 设定打开网页。路径不同的独立副本允许同时运行。
如果旧 v1.0.0 正在【同一目录】运行，新版会尝试通过其原有退出事件让它安全退出；如果旧版在【另一个目录】，请先从旧版托盘手动退出，否则两个版本会各自启动定时器。原版 AHK 同样需要手动退出。
启动时先验证新版配置、再替换运行中的 v2 实例：错误配置不会因为一次失败的重新启动而关闭原本正常运行的实例。

五、实现方式和兼容性

- Main.cmd 临时调用系统 Windows PowerShell 5.1 来启动 Start-Background.ps1。
- 启动器通过 System.Diagnostics.ProcessStartInfo，设置 UseShellExecute=false、CreateNoWindow=true 来创建后台 PowerShell 子进程；不依赖 -WindowStyle Hidden 作为主要隐藏机制，避免 Windows Terminal 对隐藏参数的忽略。
- 常驻端 RoundCheckWebpage.ps1 使用 WinForms ApplicationContext、NotifyIcon、ContextMenuStrip 和单线程 UI Timer，不创建主界面窗口。
- 在加载和创建 WinForms UI 之前，用 Add-Type 内嵌的 C# 调用 user32.dll SetProcessDpiAwarenessContext(-4)，必要时对线程使用 SetThreadDpiAwarenessContext(-4)，核实 Per-Monitor V2 DPI 是否成功。PMv2 要求 Windows 10 1703 或更高版本。
- 所有启动参数位于纯文本 Configuration.txt。Add-Type 只在运行时使用 Windows/.NET Framework 自带工具构建互操作类型，不提供编译好的 EXE 或 DLL。
- 启动时遇到严重配置或运行错误，会尝试弹消息框，并把详细异常写入 _Logs/error.log；配置重载或打开网址失败会尝试发送托盘气泡并记录错误。
- 后台已正常运行时，仅应出现托盘图标；启动时短暂命令窗口、故障对话框、编辑配置时的记事本窗口均属于用户主动操作或异常处理。
- 不修改系统全局 PowerShell 执行策略；启动时的 -ExecutionPolicy Bypass 仅限该进程，组织安全策略可能禁止该方式执行。
- 在只读目录可能无法生成 _Logs 下的错误日志；推荐放在个人可写目录中。
- Windows 系统设置可能隐藏通知和托盘图标；多屏 DPI 效果需 Windows 实机检查。
- 没有自动开机启动。需要时可在 Windows 用户启动文件夹放 Main.cmd 的快捷方式。
- 用同一配置打开上千网址可能导致浏览器和系统资源占用很高；请按实际需求安排网址数量及周期。

六、Windows 实机验收（尚未执行）

本次交付在非 Windows 环境进行源码检查和打包检查，未执行 Windows PowerShell 5.1 / WinForms / 托盘 / 浏览器实机测试。请在目标系统逐项验收：

[ ] 01. 解压到含空格、中文的普通路径，双击 Main.cmd，确认不留下常驻 CMD/PowerShell 窗口，并出现 RoundCheckWebpage 托盘图标。
[ ] 02. 默认配置启动，确认立即打开第一条猫眼 URL，第二条被注释的 URL 不打开；且所有 ?、&、= 参数保留。
[ ] 03. 在 Configuration.txt 里增加 2—3 条易于辨认的网址，重载后执行「立即打开全部网址」，检查每条按文件顺序被请求打开。
[ ] 04. 加入同一个测试 URL 两行，确认程序每轮确实执行两次打开请求。浏览器可能自行合并或聚焦重复页面，故以请求行为/浏览器实际表现综合判断。
[ ] 05. 把 IntervalMinutes 改为 1，右键重载；等待约 1 分钟，确认每轮每个 URL 各打开一次，再过约 1 分钟重复一次。然后改回 30。
[ ] 06. 设 OpenOnStart=false，退出程序重启，确认启动时不立即开页而是等待完整周期；改回 true 后重启能立即打开。
[ ] 07. 暂停超过一个周期，无自动打开；暂停时手动打开仍有效；恢复后从零开始完整计时，不追补错过的多轮。
[ ] 08. 设置 IntervalMinutes=0、重复 IntervalMinutes、删掉所有网址、混入非法网址、输入未知字段并逐次尝试重载：每种情况应报错，原已加载的正确配置继续运行。检查 _Logs/error.log。
[ ] 09. 运行中直接删除 Configuration.txt，重载应报错；还原文件并重载应恢复。关闭后无配置启动应明确报错（若同目录仍有旧 Config.ini，则应优先验证迁移行为）。
[ ] 10. 多次连续双击 Main.cmd，确认只剩一个当前目录的 RoundCheckWebpage.ps1 常驻实例；每次成功重启按 OpenOnStart 决定是否立即开页。
[ ] 11. 把 v1 旧 Config.ini 放在同一目录，移走 Configuration.txt，启动后应生成 Configuration.txt 且原禁用 URL 仍是注释；验证旧文件保留未改变。
[ ] 12. 如果旧 v1 仍在同一目录运行，启动新 v2 应请求旧版退出；旧 v1 若在另一目录，请主动退出，避免两套脚本并行。
[ ] 13. 在 Windows Terminal 为默认终端时启动，确认没有常驻控制台；在 4K 缩放 150%、200%、250% 及多显示器不同缩放下查看托盘菜单清晰度。
[ ] 14. 让电脑睡眠超过周期，唤醒后确认不会一次性连续打开很多轮网页；退出托盘后确认自动打开停止。
[ ] 15. 正常工作后检查任务管理器命令行列可区分 RoundCheckWebpage.ps1；发现问题请保留 _Logs/error.log 和复现步骤。

七、文件清单

Main.cmd                            双击入口（短暂）
Start-Background.ps1                 使用 CreateNoWindow 的临时启动器
RoundCheckWebpage.ps1                常驻主脚本，PowerShell + 内嵌 C# / Win32
Configuration.txt                    周期 + 任意多条 URL 的唯一现行配置
README.txt                           本说明、限制及实机验收项
LICENSE.txt                          本次重构源码的 MIT 许可证
.gitignore                           Git 忽略运行日志
_Logs/                               运行时错误日志目录（生成 error.log）
Legacy/Round_Check_GT_Ticket.ahk     最初 AHK 源码备份
Legacy/Round_Check_GT_Ticket_PS51_v1.0.0.zip  上一版完整交付备份

八、版本历史

AHK 原版：AHK v2；启动后立即打开 Url1；实际每 30 分钟再次打开；Url2 注释禁用；#SingleInstance Force；没有自定义热键。原 AHK 注释曾写 60 分钟，实际 N=30。
v1.0.0（2026-11-18）：重构为 PowerShell 5.1 常驻脚本；Config.ini 两个固定网址及启用开关；后台启动、托盘、暂停/恢复、手动执行、单实例替换、DPI 处理、错误记录。
v2.0.0（2026-11-18）：项目更名 RoundCheckWebpage；统一使用 Configuration.txt 设置周期和任意多条逐行 URL；支持逐行注释、URL 重复、全量校验后热重载；保留 OpenOnStart；缺少 TXT 时支持从 v1 Config.ini 一次性转换；尝试接管同目录 v1 实例；保留原 AHK 与完整 v1.0.0 备份；扩展多 URL 实机测试项目。

授权说明：新编写的 PowerShell 部分采用随包 MIT License；Legacy 内原文件为兼容与回退保留，不宣称替原作者重新授权。
