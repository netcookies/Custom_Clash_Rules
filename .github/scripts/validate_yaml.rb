#!/usr/bin/env ruby
# frozen_string_literal: true

# 校验 convert_yaml.sh 生成的 YAML：
# - YAML 可解析，且顶层是映射；
# - RULE-SET 引用的 rule-provider 存在；
# - rule-provider 字段完整、behavior/format 合法；
# - 每个配置以 MATCH 规则结尾；
# - Custom_Stash_Full 必须使用 domain 类型的 gfw/google-cn/category-games-cn
#   provider，不能残留对应的 GEOSITE 规则。

require 'yaml'

errors = []
yaml_files = Dir.glob('yaml/*.yaml').sort

if yaml_files.empty?
  warn '❌ yaml/ 目录下没有生成任何 YAML'
  exit 1
end

def load_yaml(path)
  YAML.load_file(path)
end

yaml_files.each do |path|
  begin
    data = load_yaml(path)
  rescue StandardError => e
    errors << "#{path}: YAML 解析失败: #{e.message}"
    next
  end

  unless data.is_a?(Hash)
    errors << "#{path}: 顶层不是映射"
    next
  end

  providers = data['rule-providers'] || {}
  rules = data['rules'] || []

  unless providers.is_a?(Hash)
    errors << "#{path}: rule-providers 不是映射"
    providers = {}
  end

  providers.each do |name, provider|
    unless provider.is_a?(Hash)
      errors << "#{path}: rule-provider #{name} 不是映射"
      next
    end

    %w[type behavior path url interval format].each do |key|
      value = provider[key]
      errors << "#{path}: rule-provider #{name} 缺少 #{key}" if value.nil? || value.to_s.empty?
    end

    behavior = provider['behavior'].to_s
    unless %w[domain ipcidr classical].include?(behavior)
      errors << "#{path}: rule-provider #{name} 的 behavior 非法: #{behavior}"
    end

    format = provider['format'].to_s
    unless %w[yaml text].include?(format)
      errors << "#{path}: rule-provider #{name} 的 format 非法: #{format}"
    end
  end

  errors << "#{path}: rules 为空" if rules.empty?
  unless rules.last.to_s.start_with?('MATCH,')
    errors << "#{path}: 最后一条规则不是 MATCH"
  end

  rules.each do |rule|
    next unless rule.is_a?(String)

    parts = rule.split(',').map(&:strip)
    next unless parts[0]&.upcase == 'RULE-SET'

    provider_name = parts[1]
    if provider_name.nil? || provider_name.empty?
      errors << "#{path}: RULE-SET 缺少 provider 名称: #{rule}"
    elsif !providers.key?(provider_name)
      errors << "#{path}: RULE-SET 引用了不存在的 provider #{provider_name}: #{rule}"
    end
  end
end

# Stash 专用配置的额外断言
stash_path = 'yaml/Custom_Stash_Full.yaml'
if File.exist?(stash_path)
  begin
    stash = load_yaml(stash_path)
    providers = stash['rule-providers'] || {}
    rules = stash['rules'] || []

    expected_providers = {
      'gfw' => 'geo/geosite/gfw.list',
      'google-cn' => 'geo/geosite/google-cn.list',
      'category-games-cn' => 'geo/geosite/category-games@cn.list'
    }

    expected_providers.each do |name, url_part|
      provider = providers[name]
      if provider.nil?
        errors << "#{stash_path}: 缺少 rule-provider #{name}"
        next
      end

      errors << "#{stash_path}: #{name} 的 behavior 必须是 domain" unless provider['behavior'] == 'domain'
      errors << "#{stash_path}: #{name} 的 format 必须是 text" unless provider['format'] == 'text'
      unless provider['url'].to_s.include?(url_part)
        errors << "#{stash_path}: #{name} 的 url 不包含 #{url_part}"
      end
    end

    expected_rules = [
      'RULE-SET,gfw,🚀 手动选择',
      'RULE-SET,google-cn,🎯 全球直连',
      'RULE-SET,category-games-cn,🎯 全球直连'
    ]
    expected_rules.each do |rule|
      errors << "#{stash_path}: 缺少规则 #{rule}" unless rules.include?(rule)
    end

    forbidden_prefixes = ['GEOSITE,gfw', 'GEOSITE,google-cn', 'GEOSITE,category-games@cn']
    rules.each do |rule|
      next unless rule.is_a?(String)
      forbidden_prefixes.each do |prefix|
        errors << "#{stash_path}: 不应残留规则 #{rule}" if rule.start_with?("#{prefix},")
      end
    end
  rescue StandardError => e
    errors << "#{stash_path}: YAML 解析失败: #{e.message}"
  end
else
  errors << "#{stash_path}: 文件不存在"
end

if errors.empty?
  puts "✅ YAML 校验通过（#{yaml_files.length} 个文件）"
else
  warn errors.map { |error| "❌ #{error}" }.join("\n")
  exit 1
end
