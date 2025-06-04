#!/bin/bash

set -e

CFG_DIR="./cfg"
YAML_DIR="./yaml"
BASE_TEMPLATE="./base/template.yaml"

mkdir -p "$YAML_DIR"

echo "📁 开始转换 ini ➜ 完整 YAML"

find "$CFG_DIR" -type f -name "*.ini" | while read -r ini; do
    base=$(basename "$ini" .ini)
    yaml="$YAML_DIR/$base.yaml"
    echo "🔧 处理 $ini → $yaml"

    # 先写入 base/template.yaml 的内容
    cat "$BASE_TEMPLATE" > "$yaml"

    # 在末尾追加 proxy-groups:
    echo -e "\nproxy-groups:" >> "$yaml"

    # 处理 custom_proxy_group 行
    grep '^custom_proxy_group=' "$ini" | while read -r line; do
        IFS='=' read -r _ content <<< "$line"
        # 解析格式：名称`类型`[代理组]`url`interval,,timeout
        IFS='`' read -r name type rest <<< "$content"

        # 提取 proxies（用 [] 包裹的部分），用 | 分隔
        proxies=""
        if [[ "$rest" =~ \[.*\] ]]; then
            proxies=$(echo "$rest" | grep -oP '\[.*?\]' | tr -d '[]' | tr '|' ',' | sed 's/, */, /g')
        fi

        # 特殊处理 proxies，逗号分隔转yaml数组格式
        IFS=',' read -ra proxy_arr <<< "$proxies"

        echo "  - name: \"$name\"" >> "$yaml"
        echo "    type: $type" >> "$yaml"

        if [ ${#proxy_arr[@]} -gt 0 ]; then
            echo -n "    proxies: [" >> "$yaml"
            for i in "${!proxy_arr[@]}"; do
                p="${proxy_arr[$i]}"
                p_trimmed="$(echo -e "${p}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                echo -n "\"$p_trimmed\"" >> "$yaml"
                if [ $i -lt $((${#proxy_arr[@]} - 1)) ]; then
                    echo -n ", " >> "$yaml"
                fi
            done
            echo "]" >> "$yaml"
        fi

        # 如果后面有 url-test 等额外参数，也可以继续解析（可扩展）
    done

    # 追加 rule-providers:
    echo -e "\nrule-providers:" >> "$yaml"

    # 处理 ruleset 行
    grep '^ruleset=' "$ini" | while read -r line; do
        IFS='=' read -r _ body <<< "$line"

        # 可能三种情况，处理区分：
        # 1. ruleset=🎯 全球直连,[]GEOSITE,private
        # 2. ruleset=🌸 红杏影视,https://xxx/xxx.list,28800

        IFS=',' read -r name url interval <<< "$body"

        # 过滤空格
        name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        interval=$(echo "$interval" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 处理 url 为空或是 [] 开头的 GEOSET 类型
        if [[ "$url" == \[*\] ]]; then
            # GEOSET 特殊处理，Clash 用 domain-set 或 geoip
            # 这里以 domain-set 举例
            key=$(echo "$name" | iconv -f utf-8 -t ascii//TRANSLIT | tr -cd 'a-zA-Z0-9' | tr '[:upper:]' '[:lower:]')
            cat >> "$yaml" <<EOF
  $key:
    type: domain-set
    behavior: classical
    path: ./ruleset/$key.yaml
    list:
      - ${url//[\[\]]/}   # 去除 []
EOF
        else
            # 普通 HTTP 规则
            key=$(echo "$name" | iconv -f utf-8 -t ascii//TRANSLIT | tr -cd 'a-zA-Z0-9' | tr '[:upper:]' '[:lower:]')
            interval=${interval:-86400}  # 默认一天

            cat >> "$yaml" <<EOF
  $key:
    type: http
    behavior: classical
    path: ./ruleset/$key.yaml
    url: "$url"
    interval: $interval
EOF
        fi
    done

    # 最后追加 rules 主规则，引用所有规则集
    echo -e "\nrules:" >> "$yaml"

    grep '^ruleset=' "$ini" | while read -r line; do
        IFS='=' read -r _ body <<< "$line"
        IFS=',' read -r name _ <<< "$body"
        key=$(echo "$name" | iconv -f utf-8 -t ascii//TRANSLIT | tr -cd 'a-zA-Z0-9' | tr '[:upper:]' '[:lower:]')

        echo "  - RULE-SET,$key,$name" >> "$yaml"
    done

    echo "  - MATCH,DIRECT" >> "$yaml"

    echo "✅ 生成完成 $yaml"
done

echo "🎉 所有 ini 文件已成功转换并合并基础配置。"

