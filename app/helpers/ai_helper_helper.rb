# frozen_string_literal: true
# AiHelperHelper module for AI Helper plugin
module AiHelperHelper
  include Redmine::WikiFormatting::CommonMark

  # Converts a given Markdown text to HTML using the Markdown pipeline.
  def md_to_html(text)
    text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    MarkdownPipeline.call(text)[:output].to_s.html_safe
  end

  # Load autocompletion configuration from YAML file
  def load_autocompletion_config
    @autocompletion_config ||= begin
      config_path = Rails.root.join('plugins', 'redmine_ai_helper', 'config', 'ai_helper', 'config.yml')
      if File.exist?(config_path)
        config_data = YAML.load_file(config_path)
        config_data['autocompletion'] || {}
      else
        {}
      end
    end
  end
end
