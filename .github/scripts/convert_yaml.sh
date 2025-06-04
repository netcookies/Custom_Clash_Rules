#!/bin/bash

set -euo pipefail

CFG_DIR="./cfg"
YAML_DIR="./yaml"
TEMPLATE="./base/template.yaml"

mkdir -p "$YAML_DIR"

echo "🔧 开始处理目录: $CFG_DIR"

# 处理一个 custom_proxy_group 条目，生成 YAML 片段
parse_custom_proxy_group() {
    local line="$1"

    # 示例格式：
    # custom_proxy_group=🇭🇰 香港节点`url-test`(港|HK|hk)`https://cp.cloudflare.com/generate_204`300,,50
    # 或
    # custom_proxy_group=🚀 手动选择`select`[]♻️ 自动选择`[]🇭🇰 香港节点`...

    local name type rest filter url interval tolerance include_all proxies

    # 先处理select类型含多个代理分组的情况
    if [[ "$line" =~ ^custom_proxy_group=([^`]+)`select`(.*)$ ]]; then
        name="${BASH_REMATCH[1]}"
        rest="${BASH_REMATCH[2]}"

        # proxies 名字列表提取
        proxies=()
        while [[ "$rest" =~ \[\]([^\[]+) ]]; do
            proxies+=("${BASH_REMATCH[1]}")
            rest="${rest#*\[\]}"
        done

        # 打印 YAML 格式
        {
            echo "- name: $name"
            echo "  type: select"
            echo -n "  proxies: ["
            local first=true
            for p in "${proxies[@]}"; do
                if $first; then
                    printf "%s" "$p"
                    first=false
                else
                    printf ", %s" "$p"
                fi
            done
            echo "]"
        }
        return 0
    fi

    # 处理 url-test 类型，带或不带正则过滤
    # 格式: custom_proxy_group=名字`url-test`(过滤正则)`url`间隔,,容忍
    # 没过滤：custom_proxy_group=名字`url-test`url间隔,,容忍

    if [[ "$line" =~ ^custom_proxy_group=([^`]+)`url-test`(\([^\)]+\))?`([^`]+)`([0-9]+),,([0-9]+)$ ]]; then
        name="${BASH_REMATCH[1]}"
        filter="${BASH_REMATCH[2]}"
        url="${BASH_REMATCH[3]}"
        interval="${BASH_REMATCH[4]}"
        tolerance="${BASH_REMATCH[5]}"
        include_all=true

        echo "- name: $name"
        echo "  type: url-test"
        echo "  include-all: true"
        if [[ -n "$filter" ]]; then
            # 去除两端括号，且加 (?i) 变成不区分大小写正则
            filter="(?i)${filter:1:-1}"
            echo "  filter: $filter"
        fi
        echo "  url: $url"
        echo "  interval: $interval"
        echo "  tolerance: $tolerance"
        return 0
    fi

    # 处理 select 但无 proxies 情况（极少）
    if [[ "$line" =~ ^custom_proxy_group=([^`]+)`select`$ ]]; then
        name="${BASH_REMATCH[1]}"
        echo "- name: $name"
        echo "  type: select"
        return 0
    fi

    echo "# 无法识别 custom_proxy_group 格式: $line" >&2
    return 1
}

# 主循环处理文件
find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"
    filename=$(basename "$file" .ini)
    yaml_file="$YAML_DIR/$filename.yaml"

    # 先复制模板到输出文件
    cp "$TEMPLATE" "$yaml_file"

    # 准备缓存文本
    rule_providers_text=""
    rules_text=""
    proxy_groups_text=""

    # 记录所有 rule-providers 名字，方便 rules 引用
    declare -a rule_providers_names=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 忽略空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*; ]] && continue

        if [[ "$line" =~ ^custom_proxy_group= ]]; then
            # 生成 proxy-groups YAML 片段
            pg_yaml=$(parse_custom_proxy_group "$line") || continue
            proxy_groups_text+="$pg_yaml"$'\n'
        elif [[ "$line" =~ ^ruleset= ]]; then
            rest=${line#ruleset=}

            # 判断是否是 rule-provider (带 [])
            if [[ "$rest" =~ ^([^,]+),\[(.*)\],([^,]+)(,([^,]+))?$ ]]; then
                # 例子： 🎯 全球直连,[]GEOSITE,cn
                # name = 🎯 全球直连
                # type = GEOSITE (或 GEOIP)
                # field = cn
                # opt = no-resolve（可选）

                name="${BASH_REMATCH[1]}"
                rp_type="${BASH_REMATCH[2]}"
                field="${BASH_REMATCH[3]}"
                opt="${BASH_REMATCH[5]:-}"

                # 特殊 FINAL 规则
                if [[ "$rp_type" == "FINAL" ]]; then
                    rules_text+="  - MATCH,$name"$'\n'
                    continue
                fi

                # 规则拼装顺序：type,field,name,opt
                rule="$rp_type,$field,$name"
                [[ -n "$opt" ]] && rule="$rule,$opt"
                rules_text+="  - $rule"$'\n'

            else
                # 可能是 HTTP 规则提供者，无 [] 标识
                # 格式: ruleset=名字,http链接,间隔
                IFS=',' read -r name url interval <<< "$rest"
                # 简单取文件名做 id
                idkey=$(basename "$url" | cut -d'.' -f1 | tr '[:upper:]' '[:lower:]')

                # 生成 rule-providers YAML 片段
                rule_providers_text+=$(cat <<EOF

  $idkey:
    type: http
    behavior: classical
    path: ./ruleset/$idkey.yaml
    url: "$url"
    interval: ${interval:-28800}
    format: text
EOF
)
                # 记录名字以便 rules 引用
                rule_providers_names+=("$idkey")
            fi
        fi
    done < "$file"

    # 写入 rule-providers
    if [[ -n "$rule_providers_text" ]]; then
        echo -e "\nrule-providers:" >> "$yaml_file"
        echo -e "$rule_providers_text" >> "$yaml_file"
    fi

    # 写入 proxy-groups
    if [[ -n "$proxy_groups_text" ]]; then
        echo -e "\nproxy-groups:" >> "$yaml_file"
        echo -e "$proxy_groups_text" >> "$yaml_file"
    fi

    # 把 rule-providers 引用加入 rules
    for rp in "${rule_providers_names[@]}"; do
        rules_text+="  - RULE-SET,$rp"$'\n'
    done

    # 写入 rules
    if [[ -n "$rules_text" ]]; then
        echo -e "\nrules:" >> "$yaml_file"
        echo -e "$rules_text" >> "$yaml_file"
    fi

    echo "✅ 已生成: $yaml_file"
done

echo "🎉 所有 ini 文件已成功转换为 YAML"

