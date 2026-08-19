# connect-git-with-github

一个 Codex skill，用于在 Windows 电脑上快速完成 Git 与 GitHub 的连接配置，并可选择开启本地仓库的实时自动同步。

## 内容

- `connect-git-with-github/SKILL.md`：完整配置流程说明
- `connect-git-with-github/scripts/git-autosync.ps1`：实时自动同步脚本

## 在新电脑上安装

1. 克隆本仓库：

```powershell
git clone https://github.com/bigeggs-gjy/connect-git-with-github.git
```

2. 把其中的 `connect-git-with-github` 文件夹复制到 Codex 的 skills 目录（通常是 `C:\Users\<你的用户名>\.codex\skills\`），复制后该目录里应直接包含 `SKILL.md`。

3. 在 Codex 里说「使用 connect-git-with-github 帮我把这台电脑的 Git 连到 GitHub」，或直接输入 `$connect-git-with-github`。
