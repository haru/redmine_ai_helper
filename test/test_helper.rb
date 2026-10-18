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

# Redmine 6.1-stable and older lack the locale-leak fix from redmine#44116, so
# a test that changes I18n.locale (e.g. a controller test exercising a
# Japanese-language user) can bleed into later tests run by the same worker.
# Reset it here so plugin test order stays independent of core's fix.
ActiveSupport::TestCase.setup do
  ::I18n.locale = ::I18n.default_locale # rubocop:disable Rails/I18nLocaleAssignment
end

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

# Assertions shared by the LLM provider tests.
module ProviderTestAssertions
  # Asserts that the provider sends a split system prompt as one system message
  # with the two parts joined and no cache marker.
  # @param provider [RedmineAiHelper::LlmClient::BaseProvider] the provider under test
  def assert_single_uncached_system_message(provider)
    instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "FIXED", variable: "VARIABLE")
    chat = provider.create_chat(instructions: instructions)
    system_messages = chat.messages.select { |m| m.role == :system }

    assert_equal 1, system_messages.size
    assert_equal "FIXED\n\nVARIABLE", system_messages.first.content
    assert_equal false, system_messages.first.cache_until_here?
  end
end
ActiveSupport.on_load(:active_support_test_case) { include ProviderTestAssertions }

# Readers and assertions for the text layer of an rbpdf PDF, shared by the
# health report PDF export tests. rbpdf writes every drawn text run into a
# content stream as a "BT x y Td ... [(text)] TJ" operation, so the runs give
# the drawn text with its position. Plain text extraction alone cannot tell a
# drawn table cell from a Markdown table line printed as text — both reach the
# text layer — which is why the run-level view exists.
module PdfTextAssertions
  # The body shared by the PDF table export tests: a 3-column and a 2-column
  # Markdown table separated by a blank line.
  TWO_TABLES_BODY = "| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n\n| x | y |\n|---|---|\n| 4 | 5 |\n"

  # One drawn text run: x and y in PDF points and the unescaped run text.
  # rbpdf writes multibyte runs as UTF-16BE, whose NUL padding bytes
  # {PdfTextAssertions.streams} already removes.
  Run = Data.define(:x, :y, :text)

  # One text-showing operation: the x, y of its "BT x y Td" positioning and
  # the content of its first string literal — rbpdf writes the run as
  # "[(text)] TJ", so the pattern takes what sits between "[(" and ")]" and
  # may carry escaped parentheses.
  RUN_PATTERN = /BT\s+(-?[\d.]+)\s+(-?[\d.]+)\s+Td.*?\[\(((?:[^\]\\]|\\.)*)\)\]\s*TJ/m

  module_function

  # Inflate the content streams of a PDF and return their concatenated text.
  # @param pdf [String] the PDF byte string
  # @return [String]
  def streams(pdf)
    pdf.b.scan(/stream\r?\n(.*?)endstream/m).map do |(data)|
      begin
        Zlib::Inflate.inflate(data)
      rescue Zlib::Error
        data
      end
    end.join.delete("\x00")
  end

  # The plain text of a PDF, with the parenthesis escapes removed.
  # @param pdf [String] the PDF byte string
  # @return [String]
  def pdf_text(pdf)
    streams(pdf).gsub(/\\([()])/, '\1')
  end

  # The drawn text runs of a PDF, in stream order.
  # @param pdf [String] the PDF byte string
  # @return [Array<PdfTextAssertions::Run>]
  def pdf_text_runs(pdf)
    streams(pdf).scan(RUN_PATTERN).map do |x, y, raw|
      Run.new(x.to_f, y.to_f, raw.gsub(/\\([()\\])/, '\1'))
    end
  end
end

module PdfTableAssertions
  # Assert that the PDF draws {PdfTextAssertions::TWO_TABLES_BODY} as two real
  # tables: every cell is in the text layer, each table's header cells share
  # one row, the two tables are drawn as two (a merged 5-column table would
  # put all five header cells on one row), the column boundaries differ, and
  # no Markdown table line reached the text layer (the pre-079 bug printed
  # "| a | b | c |" as plain text).
  # @param pdf [String] the PDF byte string
  # @return [void]
  def assert_pdf_draws_two_tables(pdf)
    runs = PdfTextAssertions.pdf_text_runs(pdf)
    assert_operator runs.size, :>=, 10, "the ten table cells must be in the PDF text layer"

    pipe_runs = runs.select { |run| run.text.start_with?("|") || run.text.include?("|---") }
    assert_empty pipe_runs, "a Markdown table line reached the text layer"

    missing = %w[a b c x y 1 2 3 4 5] - runs.map(&:text)
    assert_empty missing, "table cells missing from the PDF text layer"

    first_header_y = header_row_y(runs, %w[a b c])
    second_header_y = header_row_y(runs, %w[x y])
    assert_not_equal first_header_y, second_header_y, "the two tables must be drawn as two tables"

    x_of_three_column = runs.find { |run| run.text == "b" }.x
    x_of_two_column = runs.find { |run| run.text == "y" }.x
    assert_not_in_delta x_of_three_column, x_of_two_column, 0.5,
                        "the 3-column and the 2-column table must have different column boundaries"
  end

  private

  # The one y coordinate shared by the given header cells.
  # @param runs [Array<PdfTextAssertions::Run>]
  # @param texts [Array<String>] the header cell texts of one table
  # @return [Float]
  def header_row_y(runs, texts)
    ys = runs.select { |run| texts.include?(run.text) }.map(&:y).uniq
    assert_equal 1, ys.size, "the header cells #{texts.inspect} must share one row"
    ys.first
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include PdfTextAssertions
  include PdfTableAssertions
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
