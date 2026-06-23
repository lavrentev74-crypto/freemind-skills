# SSH Key Setup

Optional — do NOT push on user.

## Steps (order is critical!)

1. Check if key exists:
   - Mac/Linux: `ls ~/.ssh/id_ed25519.pub`
   - Windows: `dir %USERPROFILE%\.ssh\id_ed25519.pub`

2. Generate if missing:
   - `ssh-keygen -t ed25519 -C "email@example.com"` (Enter 3 times)

3. Copy to server:
   - Mac/Linux: `ssh-copy-id root@SERVER_IP`
   - Windows: `type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@SERVER_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"`

4. **VERIFY** — new terminal window: `ssh root@SERVER_IP` (must login WITHOUT password)
   **If asks for password — STOP. Do not proceed to step 5.**

5. Only after verification — ask "Disable password login?":
   ```bash
   ssh root@SERVER_IP "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl reload sshd"
   ```

6. Add key to hosting panel:
   - **AdminVPS:** Dashboard → "SSH ключи" → "Добавить ключ" → paste `~/.ssh/id_ed25519.pub`, name it, check "Автоматически добавлять на новые сервера"
   - **Others:** find "SSH Keys" section in hosting panel
