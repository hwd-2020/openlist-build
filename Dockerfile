# 用本地已有的上游镜像做底，只替换二进制。
# 这样构建时不需要联网、不需要拉任何镜像。
ARG BASE=openlistteam/openlist:v4.2.9
FROM ${BASE}

COPY --chmod=755 --chown=1001:1001 openlist /opt/openlist/openlist
