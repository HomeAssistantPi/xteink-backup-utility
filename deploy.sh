#!/usr/bin/env bash
# ==============================================================================
# GitHub Project Initializer & Uploader
# ==============================================================================

# 1. Install Git if missing (Distro-aware)
if ! command -v git &> /dev/null; then
    echo "Git not found. Installing..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            opensuse*|suse) sudo zypper install -y git-core ;;
            debian|ubuntu) sudo apt install -y git ;;
            fedora) sudo dnf install -y git ;;
            arch) sudo pacman -S --noconfirm git ;;
        esac
    fi
fi

# 2. Collect GitHub info
read -p "GitHub Username: " GH_USER
read -p "Repository Name (e.g., xteink-pro4-utility): " GH_REPO
echo "Note: You need a Personal Access Token (PAT) for the password."
read -sp "GitHub Token: " GH_TOKEN
echo -e "\n"

# 3. Configure Git Identity (Only if not set)
if [ -z "$(git config --global user.email)" ]; then
    read -p "Enter your Email for Git: " GH_EMAIL
    git config --global user.email "$GH_EMAIL"
fi
if [ -z "$(git config --global user.name)" ]; then
    read -p "Enter your Name for Git: " GH_NAME
    git config --global user.name "$GH_NAME"
fi

# 4. Initialize and Commit
echo "Initializing local repository..."
git init
git add .
git commit -m "Initial commit: MIT Edition"
git branch -M main

# 5. Remote and Push
# We embed the token in the URL so it doesn't prompt you for a password
REMOTE_URL="https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git"

echo "Pushing to GitHub..."
git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"
git push -u origin main

# 6. Cleanup (Security)
# We remove the token from the remote URL so it isn't stored in plain text in .git/config
git remote set-url origin "https://github.com/${GH_USER}/${GH_REPO}.git"

echo "================================================"
echo "Done! Check your project at:"
echo "https://github.com/${GH_USER}/${GH_REPO}"
echo "================================================"
