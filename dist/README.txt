MarkView 飞书风 Markdown 查看器（macOS）
=====================================
签名：ad-hoc（无 Apple 身份，跨机器分发时需要「右键打开」一次）

⚠️  说明：未走 Apple 公证，对方机器首次打开会弹 Gatekeeper 警告。
      第一次必须在 Finder 右键 MarkView.app → 打开 → 打开，
      之后就能双击了。系统设置里"仍要打开"也可以。

【要分发的文件】dist/MarkView-adhoc.zip  ← 这一个就够了

三种安装方式（任选其一）：

【方式 1：自动脚本（推荐）】
  双击 install.command，按提示输入开机密码即可。
  脚本会自动：解压 ad-hoc.zip → 拷到 /Applications → 摘掉隔离标记

【方式 2：手动 + 终端命令】
  1. 双击 MarkView-adhoc.zip 解压得到 MarkView-adhoc.app
  2. 把它改名为 MarkView.app 拖进 /Applications 文件夹
  3. 打开 终端（Terminal.app），粘贴执行：
       xattr -dr com.apple.quarantine /Applications/MarkView.app
  4. 在 Finder 里到 /Applications，右键 MarkView.app → 打开
  5. 弹窗里也点「打开」（只这一次需要）
  6. 之后就能双击了

【方式 3：仅右键打开（不摘隔离标记）】
  1. 同上 1-2 步装好
  2. 在 Finder 里到 /Applications
  3. 右键（不是双击）MarkView.app → 选择「打开」
  4. 弹窗里也点「打开」（只这一次需要）
  5. 之后就能双击了

如果都不行：在 系统设置 → 隐私与安全性 → 安全性，往下翻到
"MarkView.app 已被阻止使用，因为它不是来自已识别的开发者"，
点右边的「仍要打开」。
