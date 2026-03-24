#!/bin/bash

set -e

CFG_DIR="./cfg"
HXMOVIE_RULE='ruleset=🌸 红杏影视,https://hk.gh-proxy.org/raw.githubusercontent.com/netcookies/Custom_Clash_Rules/main/rules/hxmovie.list,28800'

sedi() {
    if sed --version >/dev/null 2>&1; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

echo "🔧 开始处理目录: $CFG_DIR"

find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"

    # === 删除无 no-resolve 的 GEOIP,cn 行 ===
    sedi '/^ruleset=🎯 全球直连,\[\]GEOIP,cn$/d' "$file"
    echo "🧹 已删除无 no-resolve 的 GEOIP,cn 行"

    # === 统一红杏影视规则 URL，并保持只存在一条 ===
    sedi '/^ruleset=🌸 红杏影视,/d' "$file"
    LAST_MATCH_LINE=$(grep -n '^ruleset=🚀 手动选择' "$file" | tail -n1 | cut -d: -f1)
    if [ -n "$LAST_MATCH_LINE" ]; then
        sedi "${LAST_MATCH_LINE}a\\
$HXMOVIE_RULE
" "$file"
        echo "➕ 已在最后一个 🚀 手动选择 后插入红杏影视规则"
    else
        echo "⚠️ 未找到 🚀 手动选择，未插入红杏影视规则"
    fi

    GROUP_LINE='custom_proxy_group=🌸 红杏影视`url-test`(红杏|红杏云|hongxingdl|hongxing|hongxingyun)`https://cp.cloudflare.com/generate_204`300,,50'
    grep -Fq "$GROUP_LINE" "$file" || sedi "/^;设置分组标志位$/i\\
$GROUP_LINE
" "$file"

    if grep -q '^custom_proxy_group=🎥 Emby`select`' "$file"; then
        ORIGINAL_LINE=$(grep '^custom_proxy_group=🎥 Emby`select`' "$file")
        [ -z "$ORIGINAL_LINE" ] && continue
        CLEANED_LINE=$(echo "$ORIGINAL_LINE" | sed 's|\[\]🌸 红杏影视`||g')
        UPDATED_LINE=$(echo "$CLEANED_LINE" | sed 's|^custom_proxy_group=🎥 Emby`select`|custom_proxy_group=🎥 Emby`select`[]🌸 红杏影视`|')
        ESC_ORIGINAL=$(printf '%s\n' "$ORIGINAL_LINE" | sed 's|[][\/.^$*]|\\&|g')
        ESC_UPDATED=$(printf '%s\n' "$UPDATED_LINE" | sed 's|[][\/.^$*]|\\&|g')
        sedi "s|$ESC_ORIGINAL|$ESC_UPDATED|" "$file"
        echo "✨ 🎥 Emby 分组更新完成：🌸 红杏影视 已在首位"
    fi

    # === GEOIP,cn 与 漏网之鱼规则调整 ===
    GEOIP_LINE_NUM=$(grep -n 'ruleset=.*\[]GEOIP,cn' "$file" | cut -d: -f1 | head -n1)
    if [ -z "$GEOIP_LINE_NUM" ]; then
        echo "⏩ 未找到 GEOIP,cn 规则，跳过 GEOIP 逻辑"
    else
        MATCH_LINE_NUM=$(grep -n -E 'ruleset=.*漏网之鱼|MATCH.*漏网之鱼' "$file" | cut -d: -f1 | head -n1)
        if [ -z "$MATCH_LINE_NUM" ]; then
            echo "⚠️ 未找到 漏网之鱼，跳过 GEOIP 逻辑"
        else
            PREV_LINE_NUM=$((MATCH_LINE_NUM - 1))
            PREV_LINE=$(sed -n "${PREV_LINE_NUM}p" "$file")

            if echo "$PREV_LINE" | grep -q 'ruleset=.*\[]GEOIP,cn,no-resolve'; then
                echo "🔧 去除 no-resolve 标志"
                FIXED_LINE=$(echo "$PREV_LINE" | sed 's|,no-resolve||')
                ESC_ORIGINAL=$(printf '%s\n' "$PREV_LINE" | sed 's|[][\/.^$*]|\\&|g')
                ESC_FIXED=$(printf '%s\n' "$FIXED_LINE" | sed 's|[][\/.^$*]|\\&|g')
                sedi "s|$ESC_ORIGINAL|$ESC_FIXED|" "$file"
            elif [ "$GEOIP_LINE_NUM" -ne "$PREV_LINE_NUM" ]; then
                echo "➕ 在漏网之鱼前插入无 no-resolve 的 GEOIP,cn"
                sedi "${MATCH_LINE_NUM}i\\
ruleset=🎯 全球直连,[]GEOIP,cn
" "$file"
            else
                echo "✅ GEOIP,cn 已正确设置在漏网之鱼前，无需更改"
            fi
        fi
    fi

    # === 自动选择存在时处理 🌀 全部节点 ===
    if grep -q '^custom_proxy_group=♻️ 自动选择`url-test`' "$file"; then
        echo "🔄 检测到 ♻️ 自动选择，处理 🌀 全部节点"

        # 1. 替换 custom_proxy_group 行末尾为 `.* 的为 `[]🌀 全部节点
        sedi -E 's/(^custom_proxy_group=.*)`\.\*$/\1`[]🌀 全部节点/' "$file"

        # 2. 删除旧的 🌀 全部节点 分组行（防止重复）
        sedi '/^custom_proxy_group=🌀 全部节点/d' "$file"

        # 3. 插入 🌀 全部节点 分组
        ALL_PROXY_GROUP_LINE='custom_proxy_group=🌀 全部节点`select`.*'
        sedi "/^;设置分组标志位$/i\\
$ALL_PROXY_GROUP_LINE
" "$file"

        echo "✨ 🌀 全部节点 分组插入 & 替换完成"
    fi

    echo "✅ 文件处理完成: $file"
done

echo "🎉 所有 ini 文件已成功更新。"
