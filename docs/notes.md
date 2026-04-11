# 1. Stage everything
git add -A

# 2. Commit
git commit -m "v0.2.1: Member view improvements, professions sidebar, changelog"

# 3. Push to remote
git push

# 4. Tag the release
git tag v0.2.1

# 5. Push the tag (triggers GitHub Actions → CurseForge)
git push origin v0.2.1