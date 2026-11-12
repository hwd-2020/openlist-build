# openlist-build

上游 [OpenListTeam/OpenList](https://github.com/OpenListTeam/OpenList) 的**打过补丁的构建产物**，自用。

这个仓库**不含上游源码**：每次构建都从上游 tag 现拉，再套 `patches/` 里的补丁。
所以升级只需要改一个版本号。

## 为什么需要补丁

### 0001 · SQLite 写锁（busy_timeout + txlock）

上游 v4.2.9 的 SQLite DSN 是：

```
<db>?_journal=WAL&_vacuum=incremental
```

（而且默认走 `glebarez/sqlite` 纯 Go 驱动，`_journal` / `_vacuum` 这两个是 `mattn/go-sqlite3` 的参数，实际被忽略。）

后果：并发写事务（WebDAV `MOVE` 每次都要写 `webdav_properties`，而且整个事务包住了云端 rename 调用）会拿到 `SQLITE_BUSY`，
被 WebDAV 层包成 `500 Internal Server Error`。

日志里能看到上千条 `database is locked`。

补丁加两个 DSN 参数：

```
&_pragma=busy_timeout(15000)&_txlock=immediate
```

两者缺一不可：

- 驱动**自带** `BUSY_TIMEOUT(5000)`，所以光靠等待会卡在 5s；
- 更关键的是 WAL 下 **deferred 事务**「先读后写」时升级写锁失败，会**立即**返回 `SQLITE_BUSY`，
  根本不经过 busy handler —— 把 timeout 调多大都没用。`_txlock=immediate` 让事务一开始就拿写锁，
  等待逻辑才生效。

实测（SQLite 3.x + WAL）：

| 场景 | 结果 |
| --- | --- |
| deferred：读 → 别人提交 → 写，`busy_timeout=15000` | 立即 `database is locked (5)` |
| `BEGIN IMMEDIATE`，写锁被占 3s，`busy_timeout=15000` | 等 2272ms 后成功 |


### 0002 · 读 rclone chunker 的分块

rclone 的 chunker 把大文件切成同目录下的 `<name>.rclone_chunk.001`、`.002`……
openlist 自带的 `Chunk` 驱动用的是另一套布局（`[openlist_chunk]<name>/0`、`/1`……），
所以 rclone 写上去的分块文件在 openlist 里只能看到一堆碎块。

补丁给 `Chunk` 驱动加一个开关 `rclone_compat`（默认 `false`，**只读**）：

- `List` 把 `*.rclone_chunk.###` 收起来，按原名合成一个文件条目；
- `Get` 对单个路径同样能识别；
- `Link` 按块序号拼接 `RangeReader`，支持任意 Range 请求；
- 写入仍然走原来的 openlist 分块布局，不受影响。

匹配用的是**纯数字后缀**，所以 rclone 失败时残留的临时对象
（`<name>.rclone_chunk.001_ab12cd`）不会被误认成正式分块。

配合 `Crypt` 驱动（密码/盐与 rclone 一致、`filename_encoding=base32768`）叠在它上面，
openlist 里看到的就是**解密后的完整文件**。

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
