#!/bin/bash

set -e

CFG_DIR="./cfg"
YAML_DIR="./yaml"
TEMPLATE="./base/template.yaml"

mkdir -p "$YAML_DIR"

echo "🔧 开始处理目录: $CFG_DIR"

find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"
    filename=$(basename "$file" .ini)
    yaml_file="$YAML_DIR/$filename.yaml"

    # 复制基础模板到新yaml文件
    cp "$TEMPLATE" "$yaml_file"

    # 清理临时变量
    unset rules
    unset rule_providers
    declare -A rule_providers
    rules=()

    echo -e "\nproxy-groups:" >> "$yaml_file"

    while IFS= read -r line; do
        # 处理 custom_proxy_group
        if [[ "$line" =~ ^custom_proxy_group= ]]; then
            name=$(echo "$line" | cut -d'=' -f2 | cut -d'`' -f1)
            type=$(echo "$line" | grep -oP '\`(select|url-test)\`' | tr -d '\`')

            if [[ "$type" == "select" ]]; then
                # 先把末尾的 .* 去掉再处理 proxies
                line_no_dotstar=$(echo "$line" | sed 's/\.\*$//')
                # proxies=$(echo "$line_no_dotstar" | grep -oP '\[\].*' | sed 's/\[\]//g' | tr '\`' '\n' | sed '/^$/d' | paste -sd, -)
                echo "  - name: $name" >> "$yaml_file"
                echo "    type: select" >> "$yaml_file"
                if [[ "$line" =~ \.\*$ ]]; then
                    echo "    include-all: true" >> "$yaml_file"
                fi
                echo "    proxies:" >> "$yaml_file"
                echo "$line_no_dotstar" | grep -oP '\[\][^`]*' | sed 's/^\[\]//g' | while read -r proxy; do
                    echo "      - $proxy" >> "$yaml_file"
                done
            elif [[ "$type" == "url-test" ]]; then
                url=$(echo "$line" | grep -oP '\`https?://[^\`]+\`' | tr -d '\`')
                interval=$(echo "$line" | grep -oP '\`\d+\`' | tr -d '\`' | head -1)
                tolerance=$(echo "$line" | grep -oP ',\d+$' | tr -d ',')        
                echo "  - name: $name" >> "$yaml_file"
                echo "    type: url-test" >> "$yaml_file"
                echo "    include-all: true" >> "$yaml_file"
                # 提取 () 中的正则内容
                raw_filter=$(echo "$line" | grep -oP '\`\([^\`]*\)\`' | tr -d '\`\(\)')
                if [[ "$raw_filter" =~ ^[^|]+(\|[^|]+)+$ ]]; then
                    # 多个用 `|` 分隔的关键词，且不含括号，判定为普通 filter
                    echo "    filter: (?i)$raw_filter" >> "$yaml_file"
                else
                    # 否则为 exclude-filter
                    # 假设格式是 ^(?!.*(xxx|yyy|zzz)).*，提取中间部分
                    temp="${raw_filter#^\?!\.\*}"
                    exclude_body="${temp%%\.\*}"
                    echo "    exclude-filter: (?i)$exclude_body" >> "$yaml_file"
                fi
                echo "    url: $url" >> "$yaml_file"
                echo "    interval: ${interval:-300}" >> "$yaml_file"
                echo "    tolerance: ${tolerance:-50}" >> "$yaml_file"
            fi

        # 处理 ruleset
        elif [[ "$line" =~ ^ruleset= ]]; then
            rest=${line#ruleset=}
            IFS=',' read -r name type field opt <<< "$rest"

            if [[ "$type" =~ ^\[\](.*)$ ]]; then
                # rule-providers 规则
                type_clean=${BASH_REMATCH[1]}
                key=""
                # FINAL 单独处理
                if [[ "$type_clean" == "FINAL" ]]; then
                    rules+=("  - MATCH,$name")
                else
                    # 生成 rules 入口
                    rule_line="  - $type_clean,$field,$name"
                    [[ -n "$opt" ]] && rule_line="$rule_line,$opt"
                    rules+=("$rule_line")
                fi
            else
                # http 类型无 [] 直接是rule-provider
                # 此时 type 是 url，field 是 interval
                key=$(basename "$type" .list | cut -d'.' -f1 | tr '[:upper:]' '[:lower:]')
                rule_providers["$key"]=$(cat <<EOF
  $key:
    type: http
    behavior: classical
    path: ./ruleset/$key.yaml
    url: "$type"
    interval: ${field:-28800}
    format: text
EOF
)
                # rules 添加对应条目
                rules+=("  - RULE-SET,$key,$name")
            fi
        fi
    done < "$file"

    # 输出 rule-providers
    if [[ ${#rule_providers[@]} -gt 0 ]]; then
        echo -e "\nrule-providers:" >> "$yaml_file"
        for key in "${!rule_providers[@]}"; do
            echo "${rule_providers[$key]}" >> "$yaml_file"
        done
    fi

    # 输出 rules
    if [[ ${#rules[@]} -gt 0 ]]; then
        echo -e "\nrules:" >> "$yaml_file"
        for r in "${rules[@]}"; do
            echo "$r" >> "$yaml_file"
        done
    fi

    echo "✅ 已生成: $yaml_file"
done

echo "🎉 所有 ini 文件已成功转换为 YAML"
