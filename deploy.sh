#!/bin/bash

hexo clean
hexo generate
git checkout main
rm -rf ./*
cp -r public/* .
rm -rf public
git add .
git commit -m "Site updated: $(date '+%Y-%m-%d %H:%M:%S')"
git checkout source
echo "Deploy complete! Now push main branch to GitHub:"
echo "  git push origin main --force"
