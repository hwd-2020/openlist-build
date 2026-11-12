# openlist-build

上游 [OpenListTeam/OpenList](https://github.com/OpenListTeam/OpenList) 的**打过补丁的构建产物**，自用。

这个仓库**不含上游源码**：每次构建都从上游 tag 现拉，再套 `patches/` 里的补丁。
所以升级只需要改一个版本号。

## 为什么需要补丁

### 0001 · SQLite busy_timeout

上游 v4.2.9 的 SQLite DSN 是：

```
<db>?_journal=WAL&_vacuum=incremental
```

（而且默认走 `glebarez/sqlite` 纯 Go 驱动，`_journal` / `_vacuum` 这两个是 `mattn/go-sqlite3` 的参数，实际被忽略。）

后果：并发写事务（WebDAV `MOVE` 每次都要写 `webdav_properties`）会直接拿到 `SQLITE_BUSY`，
被 WebDAV 层包成 `500 Internal Server Error`。

实测：6 个并发 `MOVE` 只有 1 个返回 201，其余 500，响应时间 1.7ms（典型的没等待就失败）。
日志里能看到 800+ 条 `database is locked`。

补丁只加一个 pragma：

```
&_pragma=busy_timeout(15000)
```

并发写会排队等待（最多 15s）而不是立刻失败。

## 构建

`Actions` → `build` → `Run workflow`，填上游 tag。

产出发布在 Releases，tag 为 `build-<upstream_tag>`，包含：

- `openlist` — 静态 linux/amd64 二进制（`CGO_ENABLED=0`，可直接跑在 Alpine 镜像里）
- `openlist.sha256`

## 打包成镜像

本仓库的 `Dockerfile` 用**已有的上游镜像**做底，只覆盖二进制，构建时不需要联网：

```bash
docker build -t openlist:<tag>-patched .
```

## 注意

这个仓库只放补丁和构建配置，**不要**提交任何配置、密码、路径或与个人数据相关的内容。
