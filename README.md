# glm-statusline
GLM status line for claude code

<p><img width="1461" height="155" alt="image" src="https://github.com/user-attachments/assets/afa62113-447b-4531-83f2-261c1adbaece" /></p>

# Info

API data reqfresh every 1 minute

You are free to change that in the script

# Setup

## 1. Place the script in ```~/.claude```

## 2. Place your api key where it says in the script

## 3. Add the statusLine block to ```~/.claude/settings.json```:
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```
