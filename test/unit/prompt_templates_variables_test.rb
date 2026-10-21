# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

# Verifies that every shipped prompt template declares exactly the variables
# its body uses, so PromptTemplate#format's strict validation cannot break a
# feature through a template/declaration mismatch.
class PromptTemplatesVariablesTest < ActiveSupport::TestCase
  TEMPLATE_ROOT = File.expand_path("../../assets/prompt_templates", __dir__)
  PLACEHOLDER = /\{([A-Za-z_][A-Za-z0-9_]*)\}/

  # Reads a template file and returns its placeholders and declared variables.
  # Throws on constructs it does not model instead of silently skipping them.
  # @param file_path [String] Path of the YAML template
  # @return [Hash] { placeholders: Array<String>, declared: Array<String> }
  def self.extract_variables(file_path)
    yaml = YAML.safe_load(File.read(file_path))
    raise ArgumentError, "#{file_path}: YAML is not a Hash" unless yaml.is_a?(Hash)
    raise ArgumentError, "#{file_path}: template is not a String" unless yaml["template"].is_a?(String)

    declared = yaml.fetch("input_variables", [])
    raise ArgumentError, "#{file_path}: input_variables is not an Array" unless declared.is_a?(Array)

    {
      placeholders: yaml["template"].scan(PLACEHOLDER).flatten.uniq,
      declared: declared.map(&:to_s).uniq
    }
  end

  def self.template_files
    Dir.glob(File.join(TEMPLATE_ROOT, "**", "*.yml")).sort
  end

  def write_yaml(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.yml")
      File.write(path, content)
      yield path
    end
  end

  context "extract_variables helper" do
    should "throw when the YAML is not a Hash" do
      write_yaml("- a\n- b\n") do |path|
        assert_raises(ArgumentError) { self.class.extract_variables(path) }
      end
    end

    should "throw when template is not a String" do
      write_yaml("template: [1]\n") do |path|
        assert_raises(ArgumentError) { self.class.extract_variables(path) }
      end
    end

    should "throw when input_variables is not an Array" do
      write_yaml("template: \"Hi {a}\"\ninput_variables: a\n") do |path|
        assert_raises(ArgumentError) { self.class.extract_variables(path) }
      end
    end

    should "report a mismatch between body and declaration" do
      write_yaml("template: \"Hi {foo}\"\ninput_variables: []\n") do |path|
        found = self.class.extract_variables(path)

        assert_equal [ "foo" ], found[:placeholders]
        assert_equal [], found[:declared]
        assert_not_equal found[:placeholders].sort, found[:declared].sort
      end
    end
  end

  context "shipped prompt templates" do
    should "be found" do
      assert_operator self.class.template_files.size, :>=, 80
    end

    should "declare exactly the placeholders used in the body" do
      mismatches = self.class.template_files.filter_map do |file|
        found = self.class.extract_variables(file)
        next if found[:placeholders].sort == found[:declared].sort

        "#{file.delete_prefix("#{TEMPLATE_ROOT}/")}: body=#{found[:placeholders].sort} declared=#{found[:declared].sort}"
      end

      assert_empty mismatches, mismatches.join("\n")
    end

    should "declare identical variables in the English and Japanese versions" do
      pairs = 0
      self.class.template_files.grep(/_ja\.yml\z/).each do |ja_file|
        en_file = ja_file.sub(/_ja\.yml\z/, ".yml")
        assert File.exist?(en_file), "missing English counterpart of #{ja_file}"

        pairs += 1
        assert_equal self.class.extract_variables(en_file)[:declared].sort,
                     self.class.extract_variables(ja_file)[:declared].sort,
                     "variables differ between #{en_file} and #{ja_file}"
      end
      assert_operator pairs, :>=, 40
    end
  end
end
