#!/bin/bash

set -e

CFG_DIR="./cfg"

echo "🔧 开始处理目录: $CFG_DIR"

find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"

    # 第一处：匹配规则下方插入 hxmovie 规则
    sed -i '/^ruleset=🚀 手动选择,\[\]GEOSITE,gfw$/a ruleset=🌸 红杏影视,https://raw.githubusercontent.com/netcookies/Custom_Clash_Rules/main/rules/hxmovie.list,28800' "$file"

    # 第二处：在“设置分组标志位”注释上方插入自定义 proxy group
    sed -i '/^;设置分组标志位$/i custom_proxy_group=🌸 红杏影视`url-test`(红杏|红杏云|hongxingdl|hongxing|hongxingyun)`https://cp.cloudflare.com/generate_204`300,,50' "$file"

    echo "✅ 文件处理完成: $file"
done

echo "🎉 所有 ini 文件已成功更新。"


