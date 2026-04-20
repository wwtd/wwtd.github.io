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

超链接语法和原生markdown没区别
```
[github](https://github.com)
```

但是如果贴图的话，用Post Asset Folder + Hexo的img语法稳一点，类似
```
{% asset_img xxx.png %}
```
需要配置_config.yml 中的post_asset_folder为true，同时将png放到md的同名目录下。
