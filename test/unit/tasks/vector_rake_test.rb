require File.expand_path("../../../test_helper", __FILE__)
require "rake"

class VectorRakeTest < ActiveSupport::TestCase
  TASK_NAME = "redmine:plugins:ai_helper:vector:ensure_indexes"

  setup do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    @task = Rake::Task[TASK_NAME]

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

class VectorGenerateRakeTest < ActiveSupport::TestCase
  GENERATE_TASK = "redmine:plugins:ai_helper:vector:generate"

  setup do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    @task = Rake::Task[GENERATE_TASK]

    TOPLEVEL_BINDING.eval("@issue_vector_db = nil; @wiki_vector_db = nil; @llm_provider = nil")

    @setting = AiHelperSetting.find_or_create
    @setting.vector_search_enabled = true
    @setting.vector_search_uri = "http://example.com"
    @setting.save!

    @issue_db = mock("IssueVectorDb")
    @wiki_db = mock("WikiVectorDb")
    RedmineAiHelper::Vector::IssueVectorDb.stubs(:new).returns(@issue_db)
    RedmineAiHelper::Vector::WikiVectorDb.stubs(:new).returns(@wiki_db)
  end

  teardown do
    @setting.vector_search_enabled = false
    @setting.save!
    Rake.application = @original_rake_application
  end

  context "generate rake task" do
    should "invoke generate_schema on both vector dbs when enabled" do
      @issue_db.expects(:generate_schema).once
      @wiki_db.expects(:generate_schema).once

      capture_generate_output
    end

    should "skip with message when vector_search_enabled is false" do
      @setting.vector_search_enabled = false
      @setting.save!

      output = capture_generate_output
      assert_match(/Vector search is not enabled\. Skipping generation\./, output[:stdout])
    end
  end

  private

  def capture_generate_output
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

class VectorDestroyRakeTest < ActiveSupport::TestCase
  DESTROY_TASK = "redmine:plugins:ai_helper:vector:destroy"

  setup do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    @task = Rake::Task[DESTROY_TASK]

    TOPLEVEL_BINDING.eval("@issue_vector_db = nil; @wiki_vector_db = nil; @llm_provider = nil")

    @setting = AiHelperSetting.find_or_create
    @setting.vector_search_enabled = true
    @setting.vector_search_uri = "http://example.com"
    @setting.save!

    @issue_db = mock("IssueVectorDb")
    @wiki_db = mock("WikiVectorDb")
    RedmineAiHelper::Vector::IssueVectorDb.stubs(:new).returns(@issue_db)
    RedmineAiHelper::Vector::WikiVectorDb.stubs(:new).returns(@wiki_db)
  end

  teardown do
    @setting.vector_search_enabled = false
    @setting.save!
    Rake.application = @original_rake_application
  end

  context "destroy rake task" do
    should "invoke destroy_schema on both vector dbs when enabled" do
      @issue_db.expects(:destroy_schema).once
      @wiki_db.expects(:destroy_schema).once

      capture_destroy_output
    end

    should "skip with message when vector_search_enabled is false" do
      @setting.vector_search_enabled = false
      @setting.save!

      output = capture_destroy_output
      assert_match(/Vector search is not enabled\. Skipping destruction\./, output[:stdout])
    end
  end

  private

  def capture_destroy_output
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

class VectorRegistRakeTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :enabled_modules, :wikis, :wiki_pages, :wiki_contents

  REGIST_TASK = "redmine:plugins:ai_helper:vector:regist"

  setup do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
    @task = Rake::Task[REGIST_TASK]

    TOPLEVEL_BINDING.eval("@issue_vector_db = nil; @wiki_vector_db = nil; @llm_provider = nil")

    @setting = AiHelperSetting.find_or_create
    @setting.vector_search_enabled = true
    @setting.vector_search_uri = "http://example.com"
    @setting.save!

    @project_with_module = Project.find(1)
    @project_with_module.enabled_modules.create!(name: "ai_helper")
    @project_without_module = Project.find(2)

    @issue_db = mock("IssueVectorDb")
    @wiki_db = mock("WikiVectorDb")
    RedmineAiHelper::Vector::IssueVectorDb.stubs(:new).returns(@issue_db)
    RedmineAiHelper::Vector::WikiVectorDb.stubs(:new).returns(@wiki_db)
    @issue_db.stubs(:index_name).returns("RedmineIssue")
    @wiki_db.stubs(:index_name).returns("RedmineWiki")
    @issue_db.stubs(:generate_schema)
    @wiki_db.stubs(:generate_schema)
  end

  teardown do
    @setting.vector_search_enabled = false
    @setting.save!
    Rake.application = @original_rake_application
  end

  context "regist rake task - US1" do
    should "only register issues from ai_helper enabled projects" do
      enabled_issues = @project_with_module.issues.to_a

      @issue_db.expects(:add_datas).with(datas: enabled_issues).once
      @wiki_db.stubs(:add_datas)
      @issue_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Issues: #{enabled_issues.count} items/, output[:stdout])
    end

    should "only register wiki pages from ai_helper enabled projects" do
      enabled_wikis = WikiPage.joins(wiki: :project).where(wikis: { project_id: @project_with_module.id }).order(:id).to_a

      @issue_db.stubs(:add_datas)
      @wiki_db.expects(:add_datas).with(datas: enabled_wikis).once
      @issue_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Wiki Pages: #{enabled_wikis.count} items/, output[:stdout])
    end

    should "register 0 items and exit normally when no projects have ai_helper enabled" do
      @project_with_module.enabled_modules.where(name: "ai_helper").destroy_all
      @project_without_module.enabled_modules.where(name: "ai_helper").destroy_all

      @issue_db.expects(:add_datas).once
      @wiki_db.expects(:add_datas).once
      @issue_db.expects(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.expects(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Issues: 0 items/, output[:stdout])
      assert_match(/Wiki Pages: 0 items/, output[:stdout])
      assert_match(/Vector data registration completed\./, output[:stdout])
    end

    should "register all issues and wiki when all projects have ai_helper enabled" do
      @project_without_module.enabled_modules.create!(name: "ai_helper")
      enabled_project_ids = Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" }).pluck(:id)
      expected_issue_count = Issue.where(project_id: enabled_project_ids).count
      expected_wiki_count = WikiPage.joins(wiki: :project).where(wikis: { project_id: enabled_project_ids }).count

      @issue_db.expects(:add_datas).once
      @wiki_db.expects(:add_datas).once
      @issue_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Issues: #{expected_issue_count} items/, output[:stdout])
      assert_match(/Wiki Pages: #{expected_wiki_count} items/, output[:stdout])
    end

    should "log cleanup counts after registration" do
      @issue_db.stubs(:add_datas)
      @wiki_db.stubs(:add_datas)
      @issue_db.expects(:clean_vector_data).returns({ deleted: 3, failed: 1 })
      @wiki_db.expects(:clean_vector_data).returns({ deleted: 2, failed: 0 })

      output = capture_regist_output
      assert_match(/Removed issue vector data: 3 \(failed: 1\)/, output[:stdout])
      assert_match(/Removed wiki vector data: 2 \(failed: 0\)/, output[:stdout])
    end
  end

  context "regist rake task - US2" do
    should "register pre-existing issues from a newly enabled project" do
      @project_without_module.enabled_modules.create!(name: "ai_helper")
      enabled_project_ids = Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" }).pluck(:id)
      expected_issue_count = Issue.where(project_id: enabled_project_ids).count

      @issue_db.expects(:add_datas).once
      @wiki_db.stubs(:add_datas)
      @issue_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Issues: #{expected_issue_count} items/, output[:stdout])
    end

    should "register pre-existing wiki pages from a newly enabled project" do
      @project_without_module.enabled_modules.create!(name: "ai_helper")
      enabled_project_ids = Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" }).pluck(:id)
      expected_wiki_count = WikiPage.joins(wiki: :project).where(wikis: { project_id: enabled_project_ids }).count

      @issue_db.stubs(:add_datas)
      @wiki_db.expects(:add_datas).once
      @issue_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Wiki Pages: #{expected_wiki_count} items/, output[:stdout])
    end
  end

  context "regist rake task - US3" do
    should "delete issue vector data from projects where ai_helper was disabled" do
      @project_with_module.enabled_modules.where(name: "ai_helper").destroy_all

      @issue_db.stubs(:add_datas)
      @wiki_db.stubs(:add_datas)
      @issue_db.expects(:clean_vector_data).returns({ deleted: 5, failed: 0 })
      @wiki_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Removed issue vector data: 5 \(failed: 0\)/, output[:stdout])
    end

    should "delete wiki vector data from projects where ai_helper was disabled" do
      @project_with_module.enabled_modules.where(name: "ai_helper").destroy_all

      @issue_db.stubs(:add_datas)
      @wiki_db.stubs(:add_datas)
      @issue_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.expects(:clean_vector_data).returns({ deleted: 3, failed: 0 })

      output = capture_regist_output
      assert_match(/Removed wiki vector data: 3 \(failed: 0\)/, output[:stdout])
    end

    should "not delete vector data from projects that remain ai_helper enabled" do
      @issue_db.stubs(:add_datas)
      @wiki_db.stubs(:add_datas)
      @issue_db.expects(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.expects(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Removed issue vector data: 0 \(failed: 0\)/, output[:stdout])
      assert_match(/Removed wiki vector data: 0 \(failed: 0\)/, output[:stdout])
    end

    should "re-register data after re-enabling a disabled project" do
      @project_with_module.enabled_modules.where(name: "ai_helper").destroy_all
      @project_without_module.enabled_modules.create!(name: "ai_helper")

      enabled_issues = @project_without_module.issues.order(:id).to_a
      WikiPage.joins(wiki: :project).where(wikis: { project_id: @project_without_module.id }).order(:id).to_a

      @issue_db.expects(:add_datas).once
      @wiki_db.expects(:add_datas).once
      @issue_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })
      @wiki_db.stubs(:clean_vector_data).returns({ deleted: 0, failed: 0 })

      output = capture_regist_output
      assert_match(/Issues: #{enabled_issues.count} items/, output[:stdout])
    end
  end

  context "regist rake task - edge cases" do
    should "skip with message when vector_search_enabled is false" do
      @setting.vector_search_enabled = false
      @setting.save!

      output = capture_regist_output
      assert_match(/Vector search is not enabled\. Skipping registration\./, output[:stdout])
    end
  end

  private

  def capture_regist_output
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
