# Keep HoverClick in Git (Bitbucket Cloud)

This project is a normal Git repository once you run `git init`. You do not
need to download a new ZIP for every source change: keep one local clone, pull
before editing, and push commits after testing.

## 1. Create an empty Bitbucket repository

1. In Bitbucket Cloud, choose **Create → Repository**.
2. Name it `hoverclick` and choose **Git**.
3. Keep it **Private** unless you want the source public.
4. Do not add a README, `.gitignore`, or sample files; this avoids a separate
   first commit that would need to be reconciled with this local project.
5. Copy the repository's **SSH** clone URL (recommended for day-to-day use).

Official Bitbucket instructions: [create a repository](https://support.atlassian.com/bitbucket-cloud/docs/create-a-repository-in-bitbucket-cloud/).

## 2. Initialize this downloaded project and push it once

Open Terminal in the extracted `HoverClick` project directory:

```bash
cd ~/Downloads/HoverClick

git init -b main
git config user.name "Your Name"
git config user.email "you@example.com"
git add .
git commit -m "Initial HoverClick project with C drawing gesture"
```

Replace the name and email with the identity you want shown on your commits.

Connect it to Bitbucket. Replace the URL with the SSH URL copied from your
new repository:

```bash
git remote add origin git@bitbucket.org:WORKSPACE/hoverclick.git
git push -u origin main
```

If you prefer HTTPS, use Bitbucket's credential manager or the repository
access-token flow. For a repository access token, Bitbucket documents the
`Repository Read` and `Repository Write` permissions and the `x-token-auth`
username. Avoid pasting a token directly into a remote URL, because that can
store it in plain text in `.git/config` and shell history. See:
[Using access tokens for a repository](https://support.atlassian.com/bitbucket-cloud/docs/using-access-tokens/).

## 3. Normal daily workflow

Before starting work, bring your local copy up to date:

```bash
git pull --rebase
```

After editing code, run tests and build the app on your Mac:

```bash
swift test
./scripts/build-macos-app.sh
open build/HoverClick.app
```

Review what changed, then save and upload the change:

```bash
git status
git diff
git add .
git commit -m "Describe the change"
git push
```

The commit is a named checkpoint. If a future change breaks something, you can
inspect the diff or return to an earlier commit without losing the project
history.

## 4. Use branches for larger experiments

For a feature you want to test separately:

```bash
git switch -c feature/my-experiment
```

After testing and committing, push the branch:

```bash
git push -u origin feature/my-experiment
```

You can merge it into `main` with a Bitbucket pull request, or locally after
you are happy with it.

## 5. How to work with ChatGPT without sending the whole project each time

Once the repository is on Bitbucket, you can share its repository URL and the
specific file/diff you want reviewed. For a focused change, the smallest useful
share is usually:

```bash
git diff
```

You can save a patch instead of zipping the full project:

```bash
git diff > hoverclick-changes.patch
```

A patch from ChatGPT can be applied to your local working copy with:

```bash
git apply hoverclick-update.patch
```

Then run tests, commit, and push. Keep the repository private; do not share
access tokens, private SSH keys, signing keys, or other credentials in chat.
