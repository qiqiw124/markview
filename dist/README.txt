MarkView 飞书风 Markdown 查看器（macOS）
=====================================
签名：ad-hoc（无 Apple 身份，未走公证）

⚠️  直接双击从浏览器下载的 MarkView.app 会被 Gatekeeper 拦，
    严重时提示「MarkView 已损坏，无法打开」。这不是包坏了，是隔离标记 + 无公证。
    按下面任一方式安装即可，装好一次以后双击就能开。

【要分发的文件】MarkView.zip（+ 本目录的 install.command）

【方式 1：自动脚本（推荐）】
  把 MarkView.zip 和 install.command 放到同一个文件夹，双击 install.command。
  脚本会自动完成：
    解压 → 清掉会破坏签名的残留文件 → 校验签名（必要时补签）
    → 拷到 /Applications → 摘掉隔离标记 → 刷新 LaunchServices
  中途要输开机密码。

【方式 2：手动 + 终端命令】
  1. 双击 MarkView.zip 解压得到 MarkView.app
  2. 拖进 /Applications
  3. 打开「终端」，粘贴执行：
       xattr -dr com.apple.quarantine /Applications/MarkView.app
  4. 打开 /Applications/MarkView.app

【方式 3：只用系统界面】
  1. 同上 1-2 步装好
  2. 双击 MarkView.app，弹出拦截时点「完成」
  3. 打开 系统设置 → 隐私与安全性 → 安全性，
     找到「MarkView 已被阻止使用…」，点「仍要打开」
  4. 再打开一次，弹窗里点「打开」

【升级】
  装了 1.0.7 及以后的版本，就用 app 内「检查更新…」（⌘U）自动升级，
  不用再走上面的流程。
