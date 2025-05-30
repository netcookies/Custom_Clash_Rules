#!/bin/bash

set -e

CFG_DIR="./cfg"
echo "🔧 开始处理目录: $CFG_DIR"

find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"

    # 插入 ruleset
    RULE_LINE='ruleset=🌸 红杏影视,https://raw.githubusercontent.com/netcookies/Custom_Clash_Rules/main/rules/hxmovie.list,28800'
    grep -Fq "$RULE_LINE" "$file" || sed -i "/^ruleset=🚀 手动选择.*$/a $RULE_LINE" "$file"

    # 插入 custom_proxy_group
    GROUP_LINE='custom_proxy_group=🌸 红杏影视`url-test`(红杏|红杏云|hongxingdl|hongxing|hongxingyun)`https://cp.cloudflare.com/generate_204`300,,50'
    grep -Fq "$GROUP_LINE" "$file" || sed -i "/^;设置分组标志位$/i $GROUP_LINE" "$file"

    # 🎥 Emby 分组强制在 select 后插入 []🌸 红杏影视`
    if grep -q '^custom_proxy_group=🎥 Emby`select`' "$file"; then
        ORIGINAL_LINE=$(grep '^custom_proxy_group=🎥 Emby`select`' "$file")

        # 删除已有 []🌸 红杏影视`（无论在哪）
        CLEANED_LINE=$(echo "$ORIGINAL_LINE" | sed 's/\[\]🌸 红杏影视`//g')

        # 重新插入到 `select` 后
        UPDATED_LINE=$(echo "$CLEANED_LINE" | sed 's/^custom_proxy_group=🎥 Emby`select`/custom_proxy_group=🎥 Emby`select`[]🌸 红杏影视`/')

        # 使用替换行更新文件
        sed -i "s|^$ORIGINAL_LINE\$|$UPDATED_LINE|" "$file"

        echo "✨ 🎥 Emby 分组更新完成：🌸 红杏影视 已在首位"
    fi

    echo "✅ 文件处理完成: $file"
done

echo "🎉 所有 ini 文件已成功更新。"
