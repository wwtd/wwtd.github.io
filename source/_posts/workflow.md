---
title: 怎么提交博客
date: 2026-03-24 18:00:00
tags:
  - hexo
---

# 怎么提交博客

当前部署的hexo，分mian 和 source两个分支。往source文件夹下写markdown，推到云端后会自动触发流水线渲染到main分支。

```bash
  touch source/_posts/xxx.md
  # write something
  hexo s
  # feel ok
  git add source/_posts/xxx.md
  git commit -m "xxxx"
  git push origin source
```
