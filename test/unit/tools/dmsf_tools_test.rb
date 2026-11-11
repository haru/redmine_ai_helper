require File.expand_path("../../../test_helper", __FILE__)

class DmsfToolsTest < ActiveSupport::TestCase
  fixtures :projects, :users

  def setup
    @old_user = User.current
    User.current = User.find(2)
    @project = Project.find(1)
    @provider = RedmineAiHelper::Tools::DmsfTools.new
    @revision = mock("DMSF current revision")
    @revision.stubs(:id).returns(87)
    @revision.stubs(:visible?).with(User.current).returns(true)
    @file = mock("DMSF document")
    @file.stubs(:id).returns(42)
    @file.stubs(:project_id).returns(@project.id)
    @file.stubs(:project).returns(@project)
    @file.stubs(:visible?).with(User.current).returns(true)
    @file.stubs(:last_revision).returns(@revision)
    @file.stubs(:name).returns("spec.pdf")
    @file.stubs(:title).returns("Technical Specification")
    @file.stubs(:description).returns("Project reference")
    @file.stubs(:dmsf_path_str).returns("Specifications/Technical Specification")
    @file.stubs(:version).returns("2.1")
    @file.stubs(:view_url).with(filename: "spec.pdf").returns("https://redmine.example/dmsf_files/42/view")
  end

  def teardown
    User.current = @old_user
  end

  test "does not expose tools when DMSF is unavailable" do
    RedmineAiHelper::Tools::DmsfTools.stubs(:enabled?).returns(false)
    result = @provider.search_files(query: "Specification")
    assert_match(/unavailable/, result[:error])
  end

  test "does not expose search without the attachment opt-in" do
    RedmineAiHelper::Tools::DmsfTools.stubs(:enabled?).returns(false)
    assert_match(/unavailable/, @provider.search_files(query: "Specification")[:error])
  end

  test "requires a separate explicit DMSF opt-in" do
    RedmineAiHelper::Tools::DmsfTools.stubs(:available?).returns(true)
    AiHelperSetting.stubs(:attachment_send_enabled?).returns(true)
    original = ENV["REDMINE_AI_HELPER_DMSF_ENABLED"]
    ENV.delete("REDMINE_AI_HELPER_DMSF_ENABLED")
    assert_equal false, RedmineAiHelper::Tools::DmsfTools.enabled?
    ENV["REDMINE_AI_HELPER_DMSF_ENABLED"] = "1"
    assert_equal true, RedmineAiHelper::Tools::DmsfTools.enabled?
  ensure
    ENV["REDMINE_AI_HELPER_DMSF_ENABLED"] = original
  end

  test "searches only explicitly authorized DMSF projects" do
    @provider.stubs(:require_enabled!)
    @provider.stubs(:authorized_projects).with(@project.id).returns([ @project ])
    scope = mock("authorized DMSF scope")
    scope.expects(:find_each).with(batch_size: 100).yields(@file)
    @provider.stubs(:dmsf_scope).with([ @project.id ]).returns(scope)

    result = @provider.search_files(query: "technical", project_id: @project.id)

    assert_equal [ 42 ], result[:documents].map { |doc| doc[:id] }
    assert_equal "2.1", result[:documents].first[:version]
    assert_equal 87, result[:documents].first[:revision_id]
    assert_equal "https://redmine.example/dmsf_files/42/view", result[:documents].first[:url]
    assert_equal 1, result[:scanned]
    assert_equal false, result[:truncated]
  end

  test "never adds invisible DMSF documents to search results" do
    @provider.stubs(:require_enabled!)
    @provider.stubs(:authorized_projects).returns([ @project ])
    @file.stubs(:visible?).with(User.current).returns(false)
    scope = mock("authorized DMSF scope")
    scope.expects(:find_each).with(batch_size: 100).yields(@file)
    @provider.stubs(:dmsf_scope).returns(scope)

    result = @provider.search_files(query: "Technical")

    assert_empty result[:documents]
  end

  test "limits metadata scans even when nothing matches" do
    @provider.stubs(:require_enabled!)
    @provider.stubs(:authorized_projects).returns([ @project ])
    scope = Object.new
    file = @file
    scope.define_singleton_method(:find_each) do |batch_size:, &block|
      2_050.times { block.call(file) }
    end
    @provider.stubs(:dmsf_scope).returns(scope)

    result = @provider.search_files(query: "not-present")

    assert_equal 2_000, result[:scanned]
    assert_equal true, result[:truncated]
    assert_empty result[:documents]
  end

  test "refuses an unauthorized DMSF file before reading its bytes" do
    @provider.stubs(:require_enabled!)
    @provider.stubs(:find_dmsf_file).returns(@file)
    @provider.stubs(:dmsf_project_allowed?).returns(false)
    @revision.expects(:file).never
    @provider.expects(:analyze_with_llm).never

    result = @provider.analyze_file(file_id: 42)
    assert_equal "DMSF document is not accessible", result[:error]
  end

  test "requires DMSF revision-view permission for file analysis" do
    @provider.stubs(:require_enabled!)
    @provider.stubs(:find_dmsf_file).returns(@file)
    @provider.stubs(:dmsf_project_allowed?).returns(true)
    User.current.stubs(:allowed_to?).with(:view_dmsf_file_revisions, @project).returns(false)
    @revision.expects(:file).never

    result = @provider.analyze_file(file_id: 42)
    assert_equal "DMSF document is not accessible", result[:error]
  end

  test "attaches a PDF in memory and returns analysis with its original link" do
    prepare_analysis_file(bytes: "%PDF-1.7 test".b)
    @provider.expects(:analyze_with_llm).with do |prompt:, file_paths:|
      prompt.include?("Key sections") && file_paths.one? &&
        file_paths.first.is_a?(RubyLLM::Attachment)
    end.returns("A technical specification summary")

    result = @provider.analyze_file(file_id: 42, question: "Key sections?")

    assert_equal "A technical specification summary", result[:analysis]
    assert_equal "https://redmine.example/dmsf_files/42/view", result[:document][:url]
    refute result.to_s.include?("/tmp/")
  end

  test "rejects oversized documents without downloading them" do
    prepare_analysis_file(bytes: "%PDF-1.7 test".b, size: 4 * 1024 * 1024)
    @attachment.expects(:download).never
    @provider.expects(:analyze_with_llm).never

    result = @provider.analyze_file(file_id: 42)
    assert_match(/size limit/, result[:error])
  end

  private

  def prepare_analysis_file(bytes:, size: bytes.bytesize)
    @provider.stubs(:require_enabled!)
    @provider.stubs(:find_dmsf_file).returns(@file)
    @provider.stubs(:dmsf_project_allowed?).returns(true)
    User.current.stubs(:allowed_to?).with(:view_dmsf_file_revisions, @project).returns(true)
    AiHelperSetting.stubs(:attachment_max_size_mb).returns(3)

    @blob = mock("ActiveStorage blob")
    @blob.stubs(:byte_size).returns(size)
    @attachment = mock("ActiveStorage attached file")
    @attachment.stubs(:attached?).returns(true)
    @attachment.stubs(:blob).returns(@blob)
    @attachment.stubs(:download).returns(bytes)
    @revision.stubs(:file).returns(@attachment)
  end
end
