# Load the Redmine helper

require "simplecov"
require "simplecov-cobertura"

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::CoberturaFormatter,
  SimpleCov::Formatter::HTMLFormatter
  # Coveralls::SimpleCov::Formatter
])

SimpleCov.start do
  root File.expand_path(File.dirname(__FILE__) + "/..")
  add_filter "/test/"
  add_filter "lib/tasks"

  add_group "Controllers", "app/controllers"
  add_group "Models", "app/models"
  add_group "Helpers", "app/helpers"

  add_group "Plugin Features", "lib/redmine_ai_helper"
end

require File.expand_path(File.dirname(__FILE__) + "/../../../test/test_helper")

ActiveSupport::TestCase.parallelize(workers: 1)

if defined?(Rails::TestUnitReporter) && Rails::TestUnitReporter.respond_to?(:executable) && !Rails::TestUnitReporter.method_defined?(:executable)
  Rails::TestUnitReporter.class_eval do
    def format_rerun_snippet(result)
      location, line =
        if result.respond_to?(:source_location)
          result.source_location
        else
          result.method(result.name).source_location
        end

      "#{self.class.executable} #{relative_path_for(location)}:#{line}"
    end
  end
end

require File.expand_path(File.dirname(__FILE__) + "/model_factory")

# Load model_factory.rb from the same folder as this file
require_relative "./model_factory"

AiHelperModelProfile.delete_all
profile = AiHelperModelProfile.create!(
  name: "Test Profile",
  llm_type: "OpenAI",
  llm_model: "gpt-3.5-turbo",
  access_key: "test_key",
  organization_id: "test_org_id",
  base_uri: "https://api.openai.com/v1"
)

setting = AiHelperSetting.find_or_create
setting.model_profile_id = profile.id
setting.additional_instructions = "This is a test system prompt."
setting.save!
