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

    cp "$TEMPLATE" "$yaml_file"
    echo -e "\nproxy-groups:" >> "$yaml_file"

    declare -A rule_providers
    rules=()

    while IFS= read -r line; do
        if [[ "$line" =~ ^custom_proxy_group= ]]; then
            name=$(echo "$line" | cut -d'=' -f2 | cut -d'\`' -f1)
            type=$(echo "$line" | grep -oP '\`(select|url-test)\`' | tr -d '\`')

            if [[ "$type" == "select" ]]; then
                proxies=$(echo "$line" | grep -oP '\[\].*' | sed 's/\[\]//g' | tr '\`' '\n' | sed '/^$/d' | paste -sd, -)
                echo "  - name: $name" >> "$yaml_file"
                echo "    type: select" >> "$yaml_file"
                echo "    proxies: [${proxies}">> "$yaml_file"
            elif [[ "$type" == "url-test" ]]; then
                filter=$(echo "$line" | grep -oP '\`\(.*\)\`' | tr -d '\`' | sed 's/^/(?i)/')
                url=$(echo "$line" | grep -oP '\`https?://[^\`]+\`' | tr -d '\`')
                interval=$(echo "$line" | grep -oP '\`\d+\`' | tr -d '\`' | head -1)
                tolerance=$(echo "$line" | grep -oP ',\d+$' | tr -d ',')
                echo "  - name: $name" >> "$yaml_file"
                echo "    type: url-test" >> "$yaml_file"
                echo "    include-all: true" >> "$yaml_file"
                [[ -n "$filter" ]] && echo "    filter: $filter" >> "$yaml_file"
                echo "    url: $url" >> "$yaml_file"
                echo "    interval: ${interval:-300}" >> "$yaml_file"
                echo "    tolerance: ${tolerance:-50}" >> "$yaml_file"
            fi

        elif [[ "$line" =~ ^ruleset= ]]; then
            rest=${line#ruleset=}
            IFS=',' read -r name type field opt <<< "$rest"

            if [[ "$type" =~ ^\[\](.*)$ ]]; then
                type_clean=${BASH_REMATCH[1]}

                if [[ "$type_clean" == "FINAL" ]]; then
                    rules+=("  - MATCH,$name")
                else
                    rule="- $type_clean,$field,$name"
                    [[ -n "$opt" ]] && rule="$rule,$opt"
                    rules+=("  $rule")
                fi
            else
                idkey=$(basename "$type" .list | cut -d'.' -f1 | tr '[:upper:]' '[:lower:]')
                rule_providers["$idkey"]=$(cat <<EOF
  $idkey:
    type: http
    behavior: classical
    path: ./ruleset/$idkey.yaml
    url: "$type"
    interval: ${field:-28800}
    format: text
EOF
)
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
]
