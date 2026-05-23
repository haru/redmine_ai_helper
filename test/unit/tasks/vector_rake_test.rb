require File.expand_path("../../../test_helper", __FILE__)
require "rake"

class VectorRakeTest < ActiveSupport::TestCase
  TASK_NAME = "redmine:plugins:ai_helper:vector:ensure_indexes"

  setup do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    @task = Rake::Task[TASK_NAME]

    # Clear memoized rake-task helpers (defined on TOPLEVEL_BINDING via `def` in vector.rake).
    TOPLEVEL_BINDING.eval("@issue_vector_db = nil; @wiki_vector_db = nil; @llm_provider = nil")

    @setting = AiHelperSetting.find_or_create
    @setting.vector_search_enabled = true
    @setting.vector_search_uri = "http://example.com"
    @setting.save!

    @issue_db = mock("IssueVectorDb")
    @wiki_db = mock("WikiVectorDb")
    RedmineAiHelper::Vector::IssueVectorDb.stubs(:new).returns(@issue_db)
    RedmineAiHelper::Vector::WikiVectorDb.stubs(:new).returns(@wiki_db)
    @issue_db.stubs(:index_name).returns("RedmineIssue")
    @wiki_db.stubs(:index_name).returns("RedmineWiki")
    @issue_db.stubs(:payload_index_declarations).returns([
      { field_name: "project_id", field_schema: "integer" },
      { field_name: "tracker_id", field_schema: "integer" }
    ])
    @wiki_db.stubs(:payload_index_declarations).returns([
      { field_name: "project_id", field_schema: "integer" }
    ])
  end

  teardown do
    @setting.vector_search_enabled = false
    @setting.save!
    Rake.application = @original_rake_application
  end

  context "ensure_indexes rake task" do
    should "skip with message when vector_search_enabled is false" do
      @setting.vector_search_enabled = false
      @setting.save!
      @issue_db.expects(:ensure_payload_indexes).never
      @wiki_db.expects(:ensure_payload_indexes).never

      output = capture_io_from_task
      assert_match(/Vector search is not enabled\. Skipping\./, output[:stdout])
    end

    should "invoke ensure_payload_indexes on both vector dbs when enabled" do
      @issue_db.expects(:ensure_payload_indexes).returns({ results: { "project_id" => :matching, "tracker_id" => :created }, schema: {} }).once
      @wiki_db.expects(:ensure_payload_indexes).returns({ results: { "project_id" => :created }, schema: {} }).once

      capture_io_from_task
    end

    should "exit 0 when every result is :created or :matching" do
      @issue_db.stubs(:ensure_payload_indexes).returns({ results: { "project_id" => :matching, "tracker_id" => :created }, schema: {} })
      @wiki_db.stubs(:ensure_payload_indexes).returns({ results: { "project_id" => :created }, schema: {} })

      output = capture_io_from_task
      assert_match(/ensure_indexes completed\./, output[:stdout])
    end

    should "continue processing and exit non-zero when any field is :mismatch (FR-008)" do
      @issue_db.stubs(:ensure_payload_indexes).returns({
        results: {
          "project_id" => :matching,
          "tracker_id" => :mismatch
        },
        schema: { "tracker_id" => "keyword" }
      })
      @wiki_db.stubs(:ensure_payload_indexes).returns({ results: { "project_id" => :created }, schema: {} })

      error = assert_raises(SystemExit) do
        capture_io_from_task
      end
      assert_not_equal 0, error.status
    end
  end

  private

  def capture_io_from_task
    @task.reenable
    stdout = StringIO.new
    original_stdout = $stdout
    $stdout = stdout
    begin
      @task.invoke
    ensure
      $stdout = original_stdout
    end
    { stdout: stdout.string }
  end
end
