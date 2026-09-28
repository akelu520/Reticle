# 签名要求（designated requirement）

ad-hoc 签名默认的签名要求是二进制的 cdhash，每次构建都会变。macOS 的隐私权限（屏幕录制等）
会记住授权时的签名要求，所以每次更新后系统都会认为“这不是之前授权的那个 App”，
即使设置里 Reticle 的开关仍显示为打开，也会继续提示需要权限。

这里的两个文件把签名要求固定为 bundle id，重新构建后权限依然有效：

- `Reticle.requirements`：主 App
- `ReticleWorker.requirements`：后台进程（屏幕录制权限按主 App 计算，这里保持一致的做法）

使用 Developer ID 正式签名时不需要这些文件：Developer ID 的默认签名要求基于团队证书，本身就是稳定的。
