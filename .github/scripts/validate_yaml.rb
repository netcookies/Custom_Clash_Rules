#!/usr/bin/env ruby
# frozen_string_literal: true

# 校验 convert_yaml.sh 生成的 YAML：
# - YAML 可解析，且顶层是映射；
# - RULE-SET 引用的 rule-provider 存在；
# - rule-provider 字段完整、behavior/format 合法；
# - 每个配置以 MATCH 规则结尾；
# - Custom_Stash_Full 全部域名规则必须使用 RULE-SET，不能残留 GEOSITE；
#   fake-ip-filter 也不能使用 geosite:，必须使用 rule-set:。

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

    if provider['url'].to_s.include?('/geo/geosite/')
      errors << "#{path}: geosite provider #{name} 的 behavior 必须是 domain" unless behavior == 'domain'
      errors << "#{path}: geosite provider #{name} 的 format 必须是 text" unless format == 'text'
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

# 所有 Stash 专用配置的通用断言
stash_paths = Dir.glob('yaml/Custom_Stash_*.yaml').sort
errors << 'yaml/Custom_Stash_*.yaml: 文件不存在' if stash_paths.empty?

stash_paths.each do |stash_path|
  begin
    stash = load_yaml(stash_path)
  rescue StandardError => e
    errors << "#{stash_path}: YAML 解析失败: #{e.message}"
    next
  end

  providers = stash['rule-providers'] || {}
  rules = stash['rules'] || []

  rules.each do |rule|
    next unless rule.is_a?(String)
    errors << "#{stash_path}: 不应残留 GEOSITE 规则 #{rule}" if rule.start_with?('GEOSITE,')
  end

  fake_ip_filter = stash.dig('dns', 'fake-ip-filter') || []
  unless fake_ip_filter.is_a?(Array)
    errors << "#{stash_path}: dns.fake-ip-filter 不是数组"
    fake_ip_filter = []
  end

  fake_ip_filter.each do |entry|
    next unless entry.is_a?(String)
    errors << "#{stash_path}: fake-ip-filter 不应使用 #{entry}" if entry.downcase.start_with?('geosite:')
  end

  fake_ip_filter.each do |entry|
    next unless entry.is_a?(String) && entry.start_with?('rule-set:')
    provider_name = entry.delete_prefix('rule-set:')
    errors << "#{stash_path}: fake-ip-filter 引用了不存在的 provider #{provider_name}" unless providers.key?(provider_name)
  end
end

# Full 模板的关键 provider / 规则断言
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

    geosite_providers = providers.count { |_, provider| provider['url'].to_s.include?('/geo/geosite/') }
    errors << "#{stash_path}: geosite provider 数量异常: #{geosite_providers}" if geosite_providers < 30

    fake_ip_filter = stash.dig('dns', 'fake-ip-filter') || []
    unless fake_ip_filter.is_a?(Array)
      errors << "#{stash_path}: dns.fake-ip-filter 不是数组"
      fake_ip_filter = []
    end

    %w[rule-set:cn rule-set:connectivity-check rule-set:private].each do |entry|
      errors << "#{stash_path}: fake-ip-filter 缺少 #{entry}" unless fake_ip_filter.include?(entry)
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
