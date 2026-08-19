---
name: connect-git-with-github
description: Connect a Windows machine's Git to GitHub with HTTPS and Git Credential Manager browser login, set the global Git identity, apply any required proxy, create or link a repository, and optionally start real-time auto-sync of local changes and branches. Use when setting up Git and GitHub on a new Windows computer or linking a project for continuous push.
---

# Connect Git with GitHub (Windows)

Goal: on a Windows machine, make Git push and pull to GitHub without repeated password prompts, and optionally keep a local repository continuously synchronized.

## 1. Check prerequisites

- `git --version` works.
- The machine can reach github.com. A proxy or VPN may be required; detect and configure it in step 4.
- Know the GitHub account login and the email associated with that account.

## 2. Set the global identity

```powershell
git config --global user.name "<Your Name>"
git config --global user.email "<email-on-github>"
git config --global init.defaultBranch main
```

Use an email that is already on the GitHub account (Settings -> Emails) so commits link to the account.

## 3. Authenticate with HTTPS + Git Credential Manager

No SSH key is needed. This uses HTTPS plus the browser OAuth flow handled by Git Credential Manager (GCM).

- Confirm a credential helper is set:

```powershell
git config --global credential.helper manager
```

- Trigger the browser login with `git credential fill`, or simply run the first `git push` or `git clone` against a GitHub URL. Complete the login in the browser.

```powershell
"protocol=https`nhost=github.com`n`n" | git credential fill
```

- Important: verify the credential was actually saved. Run `cmdkey /list` and confirm a target `LegacyGeneric:target=git:https://github.com` exists. If it is missing after login, save it immediately:

```powershell
$out = "protocol=https`nhost=github.com`n`n" | git credential fill
# Parse username and password from $out, then store them:
"protocol=https`nhost=github.com`nusername=<user>`npassword=<token>`n`n" | git credential-manager store
```

This is the main gotcha: GCM can return the token without persisting it. Always check `cmdkey /list` after the first login.

## 4. Configure a proxy only when GitHub is unreachable directly

Read the Windows system proxy:

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable, ProxyServer
```

If a proxy is enabled (for example `127.0.0.1:7897`), scope it to GitHub so other Git hosts are unaffected:

```powershell
git config --global http.https://github.com.proxy http://127.0.0.1:<port>
```

Test with `git ls-remote https://github.com/<owner>/<repo>.git`. Remove it later with:

```powershell
git config --global --unset http.https://github.com.proxy
```

## 5. Create or link a repository

Repositories are named by project, not by date or quarter.

- Create the GitHub repo either on the web or with the GitHub API using the cached token (retrieve it with `git credential fill`, then call `POST /user/repos` with `Authorization: Bearer <token>`).
- Connect the local folder:

```powershell
git init
git branch -M main
git remote add origin https://github.com/<owner>/<repo>.git
git add -A
git commit -m "Initial commit"
git push -u origin main
```

## 6. Optional real-time auto-sync

Use the bundled script `scripts/git-autosync.ps1`. It watches a repository, waits for a short quiet period after file changes, then auto-commits and pushes the current branch. It follows branch switches and pushes new branches after their first commit.

Start it hidden with logging:

```powershell
Start-Process pwsh -ArgumentList `
  '-NoProfile','-ExecutionPolicy','Bypass','-File','<skill>\scripts\git-autosync.ps1',
  '-Path','<repo>','-Push','-LogFile','<log-file>' -WindowStyle Hidden
```

Keep the log file and pid file outside the watched repository so the watcher does not commit them. Stop it with `Stop-Process -Id <pid>`.

## 7. Notes

- This is HTTPS + OAuth, not SSH. The GitHub SSH keys page stays empty; the authorization appears under Settings -> Applications -> Authorized OAuth Apps as "Git Credential Manager". Switch to SSH only if the user explicitly prefers it.
- Auto-sync makes a commit on every change and suits a single-person real-time backup. For collaboration or clean history, prefer manual `git add`, `git commit`, and `git push`.
- Keep large binaries and secrets out of Git with `.gitignore`.
