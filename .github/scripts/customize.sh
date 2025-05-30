#!/bin/bash

set -e

CFG_DIR="./cfg"
echo "🔧 开始处理目录: $CFG_DIR"

find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"

    # 第一条要插入的 ruleset 行
    RULE_LINE='ruleset=🌸 红杏影视,https://raw.githubusercontent.com/netcookies/Custom_Clash_Rules/main/rules/hxmovie.list,28800'

    # 如果未包含，则插入到指定 ruleset 行下方
    grep -Fq "$RULE_LINE" "$file" || sed -i "/^ruleset=🚀 手动选择.*$/a $RULE_LINE" "$file"

    # 第二条要插入的 custom_proxy_group 行（注意反引号需转义）
    GROUP_LINE='custom_proxy_group=🌸 红杏影视`url-test`(红杏|红杏云|hongxingdl|hongxing|hongxingyun)`https://cp.cloudflare.com/generate_204`300,,50'

    # 如果未包含，则插入到注释上方
    grep -Fq "$GROUP_LINE" "$file" || sed -i "/^;设置分组标志位$/i $GROUP_LINE" "$file"

    echo "✅ 文件处理完成: $file"
done

echo "🎉 所有 ini 文件已成功更新。"

