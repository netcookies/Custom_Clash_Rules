#!/bin/bash
set -e

CFG_DIR="./cfg"
OUT_DIR="./yaml"
TEMPLATE="./base/template.yaml"
RULESET_DIR="./ruleset"

mkdir -p "$OUT_DIR"
mkdir -p "$RULESET_DIR"

echo "🔧 开始转换 ini -> yaml..."

find "$CFG_DIR" -type f -name "*.ini" | while read -r file; do
    echo "📝 处理文件: $file"
    base_name=$(basename "$file" .ini)
    yaml_file="$OUT_DIR/$base_name.yaml"

    echo "---" > "$yaml_file"

    # 合并模板
    if [ -f "$TEMPLATE" ]; then
        cat "$TEMPLATE" >> "$yaml_file"
        echo "" >> "$yaml_file"
    fi

    echo "proxy-groups:" >> "$yaml_file"

    grep '^custom_proxy_group=' "$file" | while read -r line; do
        name=$(echo "$line" | cut -d'=' -f2 | cut -d'`' -f1)
        type=$(echo "$line" | grep -o '`[^`]*`' | sed -n 1p | tr -d '`')

        # select 类型
        if [[ "$type" == "select" ]]; then
            proxies=$(echo "$line" | sed 's/.*select`//' | grep -o '\[\][^`]*`' | sed 's/\[\]\(.*\)`/\1/' | awk '{ORS=", "} {print}' | sed 's/, $//')
            echo "  - name: $name" >> "$yaml_file"
            echo "    type: select" >> "$yaml_file"
            echo "    proxies: [${proxies}]" >> "$yaml_file"

        # url-test 类型
        elif [[ "$type" == "url-test" ]]; then
            content=$(echo "$line" | cut -d'`' -f3-)
            filter=$(echo "$content" | grep -o '^(.*)' || true)
            url=$(echo "$content" | grep -o 'https[^`]*')
            interval=$(echo "$content" | sed 's/.*`//;s/,,.*//')
            tolerance=$(echo "$content" | sed 's/.*,,//')

            echo "  - name: $name" >> "$yaml_file"
            echo "    type: url-test" >> "$yaml_file"
            echo "    include-all: true" >> "$yaml_file"
            if [[ -n "$filter" ]]; then
                echo "    filter: (?i)${filter:1:-1}" >> "$yaml_file"
            fi
            echo "    url: $url" >> "$yaml_file"
            echo "    interval: $interval" >> "$yaml_file"
            echo "    tolerance: $tolerance" >> "$yaml_file"
        fi
    done

    echo "" >> "$yaml_file"
    echo "rule-providers:" >> "$yaml_file"

    grep '^ruleset=' "$file" | while IFS=',' read -r head ruleurl interval; do
        id=$(echo "$head" | cut -d'=' -f2 | sed 's/.*,//;s/ //g')
        idkey=$(basename "$ruleurl" .list | cut -d'.' -f1)

        if [[ "$ruleurl" == \[\]* ]]; then
            continue  # GEOIP/MATCH 类型跳过
        fi

        echo "  $idkey:" >> "$yaml_file"
        echo "    type: http" >> "$yaml_file"
        echo "    behavior: classical" >> "$yaml_file"
        echo "    path: ./ruleset/$idkey.yaml" >> "$yaml_file"
        echo "    url: \"$ruleurl\"" >> "$yaml_file"
        echo "    interval: ${interval:-86400}" >> "$yaml_file"
        echo "    format: text" >> "$yaml_file"
    done

    echo "" >> "$yaml_file"
    echo "rules:" >> "$yaml_file"

    grep '^ruleset=' "$file" | while IFS=',' read -r rule1 rule2 rule3 rule4; do
        name=$(echo "$rule1" | cut -d'=' -f2)
        target=$(echo "$rule2" | sed 's/\[\]//g')

        if [[ "$target" == "GEOIP" ]]; then
            echo "  - GEOIP,$rule3,$name${rule4:+,$rule4}" >> "$yaml_file"
        elif [[ "$target" == "FINAL" ]]; then
            echo "  - MATCH,$name" >> "$yaml_file"
        fi
    done

    echo "✅ 输出完成: $yaml_file"
done

echo "🎉 全部 ini -> yaml 转换完成！"

