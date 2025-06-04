#!/bin/bash

set -euo pipefail

CFG_DIR="./cfg"
YAML_DIR="./yaml"
TEMPLATE_FILE="./base/template.yaml"

mkdir -p "$YAML_DIR"

echo "🔧 开始处理目录: $CFG_DIR"

find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"
    base_name=$(basename "$file" .ini)
    yaml_file="$YAML_DIR/$base_name.yaml"

    # 写入模板内容开头
    if [[ -f "$TEMPLATE_FILE" ]]; then
        cat "$TEMPLATE_FILE" > "$yaml_file"
        echo "" >> "$yaml_file"
    else
        echo "# 生成自 $file" > "$yaml_file"
    fi

    # 初始化 rules 和 proxy_groups 临时存储
    rules_lines=()
    proxy_groups_lines=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*; ]] && continue

        if [[ "$line" =~ ^ruleset= ]]; then
            val="${line#ruleset=}"
            # 判断是否rule-provider（包含 []）
            if [[ "$val" =~ ^([^,]+),\[\]([^,]+),([^,]+)(,([^,]+))?$ ]]; then
                # 格式：name,[]type,subname[,option]
                name="${BASH_REMATCH[1]}"
                rtype="${BASH_REMATCH[2]}"
                subname="${BASH_REMATCH[3]}"
                option="${BASH_REMATCH[5]:-}"

                if [[ "$rtype" == "FINAL" ]]; then
                    # MATCH 类型
                    rules_lines+=("  - MATCH,$name")
                else
                    # 普通 GEOIP、GEOSITE 类型，生成缩进注意
                    if [[ -n "$option" ]]; then
                        rules_lines+=("  - $rtype,$subname,$name,$option")
                    else
                        rules_lines+=("  - $rtype,$subname,$name")
                    fi
                fi

            elif [[ "$val" =~ ^([^,]+),(https?://[^,]+),([0-9]+)$ ]]; then
                # 格式: name,url,interval 无 []
                name="${BASH_REMATCH[1]}"
                url="${BASH_REMATCH[2]}"
                interval="${BASH_REMATCH[3]}"
                key=$(echo "$name" | iconv -f utf-8 -t ascii//TRANSLIT | tr ' ' '_' | tr -cd '[:alnum:]_')
                # rule-provider 格式
                cat >> "$yaml_file" <<EOF

$key:
  type: http
  behavior: classical
  path: ./ruleset/$key.yaml
  url: "$url"
  interval: $interval
  format: text
EOF

            else
                echo "⚠️ 未识别的 ruleset 格式: $val"
            fi

        elif [[ "$line" =~ ^custom_proxy_group= ]]; then
            # 去掉前缀
            content=${line#custom_proxy_group=}

            # 取名称和类型
            name=${content%%\`*} # `前部分是name
            rest=${content#*\`}  # 去掉name和第一个反引号

            # 取类型（select, url-test）
            type_val=${rest%%\`*}

            if [[ "$type_val" == "select" ]]; then
                # 取所有 []后代理名
                proxies=()
                proxy_str=${content#*select\`}
                while [[ "$proxy_str" =~ \[\]([^`\[]+) ]]; do
                    proxies+=("${BASH_REMATCH[1]}")
                    proxy_str=${proxy_str#*\[\]*}
                done
                proxies_joined=$(IFS=,; echo "${proxies[*]}")

                proxy_groups_lines+=("  - name: $name")
                proxy_groups_lines+=("    type: select")
                proxy_groups_lines+=("    proxies: [$proxies_joined]")

            elif [[ "$type_val" == "url-test" ]]; then
                # 取 filter (括号内正则)
                filter=""
                if [[ "$content" =~ \`(\(.*\))\` ]]; then
                    filter="${BASH_REMATCH[1]}"
                    filter="(?i)$filter"
                fi

                # 取 url
                url=""
                if [[ "$content" =~ \`(https?://[^`]+)\` ]]; then
                    url="${BASH_REMATCH[1]}"
                fi

                # 取 interval 和 tolerance
                interval=300
                tolerance=50
                if [[ "$content" =~ \`([0-9]+),,([0-9]+)\` ]]; then
                    interval="${BASH_REMATCH[1]}"
                    tolerance="${BASH_REMATCH[2]}"
                fi

                proxy_groups_lines+=("  - name: $name")
                proxy_groups_lines+=("    type: url-test")
                proxy_groups_lines+=("    include-all: true")
                [[ -n "$filter" ]] && proxy_groups_lines+=("    filter: $filter")
                proxy_groups_lines+=("    url: $url")
                proxy_groups_lines+=("    interval: $interval")
                proxy_groups_lines+=("    tolerance: $tolerance")
            else
                echo "⚠️ 未识别的 custom_proxy_group 类型: $type_val"
            fi

        fi

    done < "$file"

    # 写入 rules 部分
    echo "rules:" >> "$yaml_file"
    for line in "${rules_lines[@]}"; do
        echo "$line" >> "$yaml_file"
    done
    echo "" >> "$yaml_file"

    # 写入 proxy-groups 部分
    echo "proxy-groups:" >> "$yaml_file"
    for line in "${proxy_groups_lines[@]}"; do
        echo "$line" >> "$yaml_file"
    done
    echo "" >> "$yaml_file"

    echo "✅ 文件处理完成: $yaml_file"
done

echo "🎉 所有 ini 文件已成功转换为 yaml。"
