require File.expand_path("../../../test_helper", __FILE__)

class RedmineAiHelper::Tools::VectorToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :wikis, :wiki_pages

  context "VectorTools" do
    setup do
      @vector_tools = RedmineAiHelper::Tools::VectorTools.new
      @mock_db = mock("vector_db")
      @mock_logger = mock("logger")
      @setting = mock("AiHelperSetting")
      @setting.stubs(:vector_search_enabled).returns(true)
      AiHelperSetting.stubs(:find_or_create).returns(@setting)
      @vector_tools.stubs(:ai_helper_logger).returns(@mock_logger)
      @mock_logger.stubs(:debug)
      @mock_logger.stubs(:error)
      User.current = User.find(1)
      Project.find(1).enable_module!(:ai_helper)
    end

    should "raise error if vector search is not enabled" do
      @setting.stubs(:vector_search_enabled).returns(false)
      assert_raises(RuntimeError, "The vector search functionality is not enabled.") do
        @vector_tools.ask_with_filter(query: "foo", k: 10, filter: {}, target: "issue")
      end
    end

    should "raise error if k is out of range" do
      assert_raises(RuntimeError, "limit must be between 1 and 50.") do
        @vector_tools.ask_with_filter(query: "foo", k: 0, filter: {}, target: "issue")
      end
      assert_raises(RuntimeError, "limit must be between 1 and 50.") do
        @vector_tools.ask_with_filter(query: "foo", k: 51, filter: {}, target: "issue")
      end
    end

    should "call vector_db and return response when target is issue" do
      @vector_tools.stubs(:vector_db).with(target: "issue").returns(@mock_db)
      @mock_db.expects(:ask_with_filter).with(query: "foo bar", k: 10, filter: {}).returns([{ "issue_id" => 1 }])
      result = @vector_tools.ask_with_filter(query: "foo bar", k: 10, filter: {}, target: "issue")
      assert_equal 1, result.first[:id]
    end

    should "call vector_db and return response when target is wiki" do
      @vector_tools.stubs(:vector_db).with(target: "wiki").returns(@mock_db)
      @mock_db.expects(:ask_with_filter).with(query: "foo bar", k: 10, filter: {}).returns([{ "wiki_id" => 1 }])
      result = @vector_tools.ask_with_filter(query: "foo bar", k: 10, filter: {}, target: "wiki")
      wiki = WikiPage.find_by(id: 1)
      assert_equal wiki.title, result.first[:title]
    end

    should "log and raise error if exception occurs" do
      @vector_tools.stubs(:vector_db).with(target: "issue").raises(StandardError.new("db error"))
      @mock_logger.expects(:error).at_least_once
      assert_raises(RuntimeError, "Error: db error") do
        @vector_tools.ask_with_filter(query: "foo", k: 10, filter: {}, target: "issue")
      end
    end

    context "ask_with_filter permission check" do
      setup do
        User.current = User.find(2)
      end

      should "filter out issues from projects where user lacks view_ai_helper permission" do
        issue = Issue.find(1)
        issue.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, issue.project).returns(false)
        @vector_tools.stubs(:vector_db).with(target: "issue").returns(@mock_db)
        @mock_db.expects(:ask_with_filter).returns([{ "issue_id" => issue.id }])

        result = @vector_tools.ask_with_filter(query: "foo", k: 10, filter: {}, target: "issue")
        assert_equal 0, result.length
      end

      should "return issues from projects where user has view_ai_helper permission" do
        issue = Issue.find(1)
        issue.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, issue.project).returns(true)
        @vector_tools.stubs(:vector_db).with(target: "issue").returns(@mock_db)
        @mock_db.expects(:ask_with_filter).returns([{ "issue_id" => issue.id }])

        result = @vector_tools.ask_with_filter(query: "foo", k: 10, filter: {}, target: "issue")
        assert_equal 1, result.length
      end

      should "filter out wiki pages from projects where user lacks view_ai_helper permission" do
        wiki = WikiPage.find(1)
        wiki.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, wiki.project).returns(false)
        @vector_tools.stubs(:vector_db).with(target: "wiki").returns(@mock_db)
        @mock_db.expects(:ask_with_filter).returns([{ "wiki_id" => wiki.id }])

        result = @vector_tools.ask_with_filter(query: "foo", k: 10, filter: {}, target: "wiki")
        assert_equal 0, result.length
      end

      should "return wiki pages from projects where user has view_ai_helper permission" do
        wiki = WikiPage.find(1)
        wiki.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, wiki.project).returns(true)
        @vector_tools.stubs(:vector_db).with(target: "wiki").returns(@mock_db)
        @mock_db.expects(:ask_with_filter).returns([{ "wiki_id" => wiki.id }])

        result = @vector_tools.ask_with_filter(query: "foo", k: 10, filter: {}, target: "wiki")
        assert_equal 1, result.length
        assert_equal wiki.title, result.first[:title]
      end
    end

    context "#create_filter" do
      should "convert filter items with _id to integer" do
        filter = [
          { key: "project_id", condition: "match", value: "123" },
        ]
        result = @vector_tools.send(:create_filter, filter)
        assert_equal [{ key: "project_id", match: { value: 123 } }], result
      end

      should "convert filter items with other keys to string" do
        filter = [
          { key: "created_on", condition: "match", value: "2024-01-01" },
        ]
        result = @vector_tools.send(:create_filter, filter)
        assert_equal [{ key: "created_on", match: { value: "2024-01-01" } }], result
      end

      should "handle lt/lte/gt/gte conditions" do
        filter = [
          { key: "priority_id", condition: "lt", value: "5" },
        ]
        result = @vector_tools.send(:create_filter, filter)
        assert_equal [{ key: "priority_id", rante: { "lt" => 5 } }], result
      end
    end

    context "#vector_db" do
      should "return IssueVectorDb for target issue" do
        RedmineAiHelper::Vector::IssueVectorDb.expects(:new).returns(:issue_db)
        @vector_tools.instance_variable_set(:@vector_db, nil)
        assert_equal :issue_db, @vector_tools.send(:vector_db, target: "issue")
      end

      should "return WikiVectorDb for target wiki" do
        RedmineAiHelper::Vector::WikiVectorDb.expects(:new).returns(:wiki_db)
        @vector_tools.instance_variable_set(:@vector_db, nil)
        assert_equal :wiki_db, @vector_tools.send(:vector_db, target: "wiki")
      end

      should "raise error for invalid target" do
        assert_raises(RuntimeError, "Invalid target: foo. Must be 'issue' or 'wiki'.") do
          @vector_tools.send(:vector_db, target: "foo")
        end
      end
    end

    should "vector_db_enabled? returns true if setting is enabled" do
      @setting.stubs(:vector_search_enabled).returns(true)
      assert_equal true, @vector_tools.send(:vector_db_enabled?)
    end

    should "vector_db_enabled? returns false if setting is disabled" do
      @setting.stubs(:vector_search_enabled).returns(false)
      assert_equal false, @vector_tools.send(:vector_db_enabled?)
    end

    context "#find_similar_issues" do
      setup do
        @issue = Issue.find(1)
        @issue.project.enable_module!(:ai_helper)
        User.current = User.find(1)
        @mock_db = mock("vector_db")
        @vector_tools.stubs(:vector_db).with(target: "issue").returns(@mock_db)
        @mock_db.stubs(:client).returns(true)
        @mock_logger.stubs(:warn)

        # Mock the IssueContentAnalyzer for hybrid query
        @mock_analyzer = mock("issue_content_analyzer")
        @mock_analyzer.stubs(:analyze).returns({
          summary: "Test summary",
          keywords: ["keyword1", "keyword2"],
        })
        RedmineAiHelper::Vector::IssueContentAnalyzer.stubs(:new).returns(@mock_analyzer)
      end

      should "raise error if vector search is not enabled" do
        @setting.stubs(:vector_search_enabled).returns(false)
        assert_raises(RuntimeError, "The vector search functionality is not enabled.") do
          @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
        end
      end

      should "raise error if k is out of range" do
        assert_raises(RuntimeError, "limit must be between 1 and 50.") do
          @vector_tools.find_similar_issues(issue_id: @issue.id, k: 0)
        end
        assert_raises(RuntimeError, "limit must be between 1 and 50.") do
          @vector_tools.find_similar_issues(issue_id: @issue.id, k: 51)
        end
      end

      should "raise error if issue not found" do
        assert_raises(RuntimeError, "Issue not found with ID: 99999") do
          @vector_tools.find_similar_issues(issue_id: 99999, k: 10)
        end
      end

      should "raise error if issue not visible" do
        # Issue.find_by should return the issue, then visible? should return false
        Issue.stubs(:find_by).with(id: @issue.id).returns(@issue)
        @issue.stubs(:visible?).returns(false)
        assert_raises(RuntimeError, "Permission denied") do
          @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
        end
      end

      should "raise error if vector search client not available" do
        @mock_db.stubs(:client).returns(false)
        assert_raises(RuntimeError, "Vector search is not enabled or configured") do
          @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
        end
      end

      should "return similar issues successfully" do
        # Create another issue for similar results
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)

        # Mock vector search results
        mock_results = [
          {
            "payload" => {
              "issue_id" => @issue.id,  # Current issue - should be filtered out
            },
            "score" => 1.0,
          },
          {
            "payload" => {
              "issue_id" => other_issue.id,
            },
            "score" => 0.85,
          },
        ]

        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)

        assert_equal 1, result.length
        assert_equal other_issue.id, result.first[:id]
        assert_equal 85.0, result.first[:similarity_score]
      end

      should "filter out issues from projects without ai_helper module" do
        # Create issue in project without ai_helper module
        other_issue = Issue.find(2)
        other_issue.project.disable_module!(:ai_helper)

        mock_results = [
          {
            "payload" => {
              "issue_id" => other_issue.id,
            },
            "score" => 0.85,
          },
        ]

        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)

        assert_equal 0, result.length
      end

      should "filter out similar issues from projects where user lacks view_ai_helper permission" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, other_issue.project).returns(false)

        mock_results = [
          {
            "payload" => { "issue_id" => other_issue.id },
            "score" => 0.85,
          },
        ]
        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
        assert_equal 0, result.length
      end

      should "return similar issues from projects where user has view_ai_helper permission" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, other_issue.project).returns(true)

        mock_results = [
          {
            "payload" => { "issue_id" => other_issue.id },
            "score" => 0.85,
          },
        ]
        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
        assert_equal 1, result.length
      end

      should "handle issues that cause generate_issue_data to fail" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)

        mock_results = [
          {
            "payload" => {
              "issue_id" => other_issue.id,
            },
            "score" => 0.85,
          },
        ]

        @mock_db.expects(:similarity_search).returns(mock_results)

        # Mock generate_issue_data to raise an error
        @vector_tools.stubs(:generate_issue_data).raises(NoMethodError.new("undefined method `id' for nil:NilClass"))

        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)

        # Should return empty array when generate_issue_data fails
        assert_equal 0, result.length
      end

      should "return empty array when no results from vector search" do
        @mock_db.expects(:similarity_search).returns([])

        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)

        assert_equal 0, result.length
      end

      should "handle nil results from vector search" do
        @mock_db.expects(:similarity_search).returns(nil)

        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)

        assert_equal 0, result.length
      end
    end

    context "#find_similar_issues with scope" do
      setup do
        @issue = Issue.find(1)
        @issue.project.enable_module!(:ai_helper)
        User.current = User.find(1)
        @mock_db = mock("vector_db")
        @vector_tools.stubs(:vector_db).with(target: "issue").returns(@mock_db)
        @mock_db.stubs(:client).returns(true)
        @mock_logger.stubs(:warn)

        @mock_analyzer = mock("issue_content_analyzer")
        @mock_analyzer.stubs(:analyze).returns({
          summary: "Test summary",
          keywords: ["keyword1", "keyword2"],
        })
        RedmineAiHelper::Vector::IssueContentAnalyzer.stubs(:new).returns(@mock_analyzer)
      end

      should "pass scope filter to similarity_search for scope current" do
        User.current.stubs(:allowed_to?).returns(true)
        @mock_db.expects(:similarity_search).with { |args|
          args[:filter] == { must: [{ key: "project_id", match: { value: @issue.project.id } }] }
        }.returns([])

        @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10, scope: "current", project: @issue.project)
      end

      should "pass scope filter to similarity_search for scope with_subprojects" do
        @issue.project.descendants.active.each { |p| p.enable_module!(:ai_helper) }
        User.current.stubs(:allowed_to?).returns(true)

        @mock_db.expects(:similarity_search).with { |args|
          args[:filter].key?(:should) || args[:filter].key?(:must)
        }.returns([])

        @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10, scope: "with_subprojects", project: @issue.project)
      end

      should "pass scope filter to similarity_search for scope all" do
        Project.active.each { |p| p.enable_module!(:ai_helper) }
        User.current.stubs(:allowed_to?).returns(true)

        @mock_db.expects(:similarity_search).with { |args|
          args[:filter].key?(:should)
        }.returns([])

        @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10, scope: "all", project: @issue.project)
      end

      should "default to with_subprojects scope when scope not specified" do
        @issue.project.descendants.active.each { |p| p.enable_module!(:ai_helper) }
        User.current.stubs(:allowed_to?).returns(true)

        expected_ids = [@issue.project.id] + @issue.project.descendants.active.pluck(:id)
        @mock_db.expects(:similarity_search).with { |args|
          filter = args[:filter]
          if expected_ids.length == 1
            filter[:must].first[:match][:value] == expected_ids.first
          else
            filter_ids = filter[:should].map { |f| f[:match][:value] }
            expected_ids.all? { |id| filter_ids.include?(id) }
          end
        }.returns([])

        @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
      end
    end

    context "find_similar_issues with hybrid query" do
      setup do
        @issue = Issue.find(1)
        @issue.project.enable_module!(:ai_helper)
        User.current = User.find(1)
        @mock_db = mock("vector_db")
        @vector_tools.stubs(:vector_db).with(target: "issue").returns(@mock_db)
        @mock_db.stubs(:client).returns(true)
        @mock_logger.stubs(:warn)

        @mock_analyzer = mock("issue_content_analyzer")
        @analysis_result = {
          summary: "Test issue about login functionality",
          keywords: ["authentication", "login", "session"],
        }
      end

      should "perform similarity search with hybrid query" do
        # Mock the IssueContentAnalyzer to return analysis result
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)
        @mock_analyzer.expects(:analyze).with(@issue).returns(@analysis_result)

        # Expect the query to be in hybrid format (Summary + Keywords + Title)
        expected_query_pattern = /Summary:.*Keywords:.*Title:/m
        @mock_db.expects(:similarity_search).with { |args|
          args[:question].match?(expected_query_pattern) && args[:k] == 10
        }.returns([])

        @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
      end

      should "include summary and keywords in query" do
        # Mock the IssueContentAnalyzer
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)
        @mock_analyzer.expects(:analyze).with(@issue).returns(@analysis_result)

        # Capture the query passed to similarity_search
        captured_query = nil
        @mock_db.expects(:similarity_search).with { |args|
          captured_query = args[:question]
          true
        }.returns([])

        @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)

        # Verify the query contains summary, keywords, and title
        assert captured_query.include?("Summary: Test issue about login functionality"),
               "Query should include the summary"
        assert captured_query.include?("Keywords: authentication, login, session"),
               "Query should include the keywords"
        assert captured_query.include?("Title: #{@issue.subject}"),
               "Query should include the issue title"
      end

      should "fallback to raw query when analyzer fails" do
        # Mock the IssueContentAnalyzer to raise an error
        mock_analyzer_that_fails = mock("failing_analyzer")
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(mock_analyzer_that_fails)
        mock_analyzer_that_fails.expects(:analyze).with(@issue).raises(StandardError.new("LLM connection failed"))

        # Expect the fallback query (raw subject + description)
        expected_raw_query = "#{@issue.subject} #{@issue.description}"
        @mock_db.expects(:similarity_search).with { |args|
          args[:question] == expected_raw_query && args[:k] == 10
        }.returns([])

        # Should not raise error, should fallback gracefully
        result = @vector_tools.find_similar_issues(issue_id: @issue.id, k: 10)
        assert_equal [], result
      end
    end

    context "#collect_permitted_project_ids" do
      setup do
        @project = Project.find(1)
        @project.enable_module!(:ai_helper)
        User.current = User.find(1)
      end

      should "return only current project id for scope current" do
        User.current.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)
        result = @vector_tools.send(:collect_permitted_project_ids, "current", @project)
        assert_equal [@project.id], result
      end

      should "return empty array when user lacks permission for scope current" do
        User.current.stubs(:allowed_to?).returns(false)
        result = @vector_tools.send(:collect_permitted_project_ids, "current", @project)
        assert_equal [], result
      end

      should "return project and subproject ids for scope with_subprojects" do
        # Enable ai_helper for subprojects and stub permissions
        subproject_ids = @project.descendants.active.pluck(:id)
        all_project_ids = [@project.id] + subproject_ids
        all_project_ids.each do |pid|
          Project.find(pid).enable_module!(:ai_helper)
        end
        User.current.stubs(:allowed_to?).returns(true)

        result = @vector_tools.send(:collect_permitted_project_ids, "with_subprojects", @project)
        assert_includes result, @project.id
        subproject_ids.each do |sid|
          assert_includes result, sid
        end
      end

      should "exclude subprojects where user lacks permission" do
        subproject = Project.find(3)
        subproject.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, subproject).returns(false)

        result = @vector_tools.send(:collect_permitted_project_ids, "with_subprojects", @project)
        assert_includes result, @project.id
        refute_includes result, subproject.id
      end

      should "return all active project ids with permission for scope all" do
        Project.active.each { |p| p.enable_module!(:ai_helper) }
        User.current.stubs(:allowed_to?).returns(true)

        result = @vector_tools.send(:collect_permitted_project_ids, "all", @project)
        Project.active.each do |p|
          assert_includes result, p.id
        end
      end

      should "exclude projects without permission for scope all" do
        excluded_project = Project.find(2)
        Project.active.each { |p| p.enable_module!(:ai_helper) }
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, excluded_project).returns(false)

        result = @vector_tools.send(:collect_permitted_project_ids, "all", @project)
        refute_includes result, excluded_project.id
      end

      should "raise ArgumentError for invalid scope" do
        assert_raises(ArgumentError) do
          @vector_tools.send(:collect_permitted_project_ids, "invalid", @project)
        end
      end
    end

    context "#build_scope_filter" do
      setup do
        @project = Project.find(1)
        @project.enable_module!(:ai_helper)
        User.current = User.find(1)
      end

      should "return must filter with single project id for scope current" do
        User.current.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)
        result = @vector_tools.send(:build_scope_filter, "current", @project)
        expected = {
          must: [
            { key: "project_id", match: { value: @project.id } }
          ]
        }
        assert_equal expected, result
      end

      should "return nil when no permitted projects for scope current" do
        User.current.stubs(:allowed_to?).returns(false)
        result = @vector_tools.send(:build_scope_filter, "current", @project)
        assert_nil result
      end

      should "return should filter with multiple project ids for scope with_subprojects" do
        subproject_ids = @project.descendants.active.pluck(:id)
        all_ids = [@project.id] + subproject_ids
        all_ids.each { |pid| Project.find(pid).enable_module!(:ai_helper) }
        User.current.stubs(:allowed_to?).returns(true)

        result = @vector_tools.send(:build_scope_filter, "with_subprojects", @project)
        assert result.key?(:should)
        result_ids = result[:should].map { |f| f[:match][:value] }
        all_ids.each { |id| assert_includes result_ids, id }
      end

      should "return must filter when with_subprojects has no subprojects with permission" do
        # Only current project has permission
        User.current.stubs(:allowed_to?).returns(false)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)

        result = @vector_tools.send(:build_scope_filter, "with_subprojects", @project)
        expected = {
          must: [
            { key: "project_id", match: { value: @project.id } }
          ]
        }
        assert_equal expected, result
      end

      should "return should filter for scope all with multiple permitted projects" do
        Project.active.each { |p| p.enable_module!(:ai_helper) }
        User.current.stubs(:allowed_to?).returns(true)

        result = @vector_tools.send(:build_scope_filter, "all", @project)
        assert result.key?(:should)
        result_ids = result[:should].map { |f| f[:match][:value] }
        Project.active.each { |p| assert_includes result_ids, p.id }
      end

      should "return must filter for scope all when only one project permitted" do
        permitted_project = Project.find(1)
        permitted_project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(false)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, permitted_project).returns(true)

        result = @vector_tools.send(:build_scope_filter, "all", @project)
        expected = {
          must: [
            { key: "project_id", match: { value: permitted_project.id } }
          ]
        }
        assert_equal expected, result
      end

      should "raise ArgumentError for invalid scope" do
        assert_raises(ArgumentError) do
          @vector_tools.send(:build_scope_filter, "invalid", @project)
        end
      end
    end

    context "#find_similar_issues_by_content" do
      setup do
        @project = Project.find(1)
        @project.enable_module!(:ai_helper)
        User.current = User.find(1)
        @mock_db = mock("vector_db")
        @vector_tools.stubs(:vector_db).with(target: "issue").returns(@mock_db)
        @mock_db.stubs(:client).returns(true)
        @mock_logger.stubs(:warn)
        @vector_tools.instance_variable_set(:@project, @project)
      end

      should "raise error if vector search is not enabled" do
        @setting.stubs(:vector_search_enabled).returns(false)
        assert_raises(RuntimeError, "Vector search is not enabled") do
          @vector_tools.find_similar_issues_by_content(subject: "Test subject", description: "Test description", k: 10)
        end
      end

      should "raise error if k is out of range" do
        assert_raises(RuntimeError, "Limit must be between 1 and 50") do
          @vector_tools.find_similar_issues_by_content(subject: "Test", description: "Test", k: 0)
        end
        assert_raises(RuntimeError, "Limit must be between 1 and 50") do
          @vector_tools.find_similar_issues_by_content(subject: "Test", description: "Test", k: 51)
        end
      end

      should "raise error if vector search client not available" do
        @mock_db.stubs(:client).returns(false)
        assert_raises(RuntimeError, "Vector search is not enabled or configured") do
          @vector_tools.find_similar_issues_by_content(subject: "Test", description: "Test", k: 10)
        end
      end

      should "return similar issues successfully" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)

        mock_results = [
          {
            "payload" => {
              "issue_id" => other_issue.id,
            },
            "score" => 0.85,
          },
        ]

        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test subject",
          description: "Test description",
          k: 10,
        )

        assert_equal 1, result.length
        assert_equal other_issue.id, result.first[:id]
        assert_equal 85.0, result.first[:similarity_score]
      end

      should "build content query correctly" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)

        expected_query_pattern = /Title:.*Test subject.*Description:.*Test description/m
        @mock_db.expects(:similarity_search).with { |args|
          args[:question].match?(expected_query_pattern) && args[:k] == 10
        }.returns([])

        @vector_tools.find_similar_issues_by_content(
          subject: "Test subject",
          description: "Test description",
          k: 10,
        )
      end

      should "filter out issues from projects without ai_helper module" do
        other_issue = Issue.find(2)
        other_issue.project.disable_module!(:ai_helper)

        mock_results = [
          {
            "payload" => {
              "issue_id" => other_issue.id,
            },
            "score" => 0.85,
          },
        ]

        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test",
          description: "Test",
          k: 10,
        )

        assert_equal 0, result.length
      end

      should "filter out issues by content from projects where user lacks view_ai_helper permission" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, other_issue.project).returns(false)

        mock_results = [
          {
            "payload" => { "issue_id" => other_issue.id },
            "score" => 0.85,
          },
        ]
        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test",
          description: "Test",
          k: 10,
        )
        assert_equal 0, result.length
      end

      should "return issues by content from projects where user has view_ai_helper permission" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)
        User.current.stubs(:allowed_to?).returns(true)
        User.current.stubs(:allowed_to?).with(:view_ai_helper, other_issue.project).returns(true)

        mock_results = [
          {
            "payload" => { "issue_id" => other_issue.id },
            "score" => 0.85,
          },
        ]
        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test",
          description: "Test",
          k: 10,
        )
        assert_equal 1, result.length
      end

      should "filter out issues that are not visible" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)
        Issue.any_instance.stubs(:visible?).returns(false)

        mock_results = [
          {
            "payload" => {
              "issue_id" => other_issue.id,
            },
            "score" => 0.85,
          },
        ]

        @mock_db.expects(:similarity_search).returns(mock_results)

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test",
          description: "Test",
          k: 10,
        )

        assert_equal 0, result.length
      end

      should "return empty array when no results from vector search" do
        @mock_db.expects(:similarity_search).returns([])

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test",
          description: "Test",
          k: 10,
        )

        assert_equal 0, result.length
      end

      should "handle nil results from vector search" do
        @mock_db.expects(:similarity_search).returns(nil)

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test",
          description: "Test",
          k: 10,
        )

        assert_equal 0, result.length
      end

      should "work with only subject provided" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)

        @mock_db.expects(:similarity_search).with { |args|
          args[:question].include?("Title: Test subject") && args[:k] == 10
        }.returns([
          {
            "payload" => { "issue_id" => other_issue.id },
            "score" => 0.75,
          },
        ])

        result = @vector_tools.find_similar_issues_by_content(
          subject: "Test subject",
          description: "",
          k: 10,
        )

        assert_equal 1, result.length
      end

      should "work with only description provided" do
        other_issue = Issue.find(2)
        other_issue.project.enable_module!(:ai_helper)

        @mock_db.expects(:similarity_search).with { |args|
          args[:question].include?("Description: Test description") && args[:k] == 10
        }.returns([
          {
            "payload" => { "issue_id" => other_issue.id },
            "score" => 0.75,
          },
        ])

        result = @vector_tools.find_similar_issues_by_content(
          subject: "",
          description: "Test description",
          k: 10,
        )

        assert_equal 1, result.length
      end
    end
  end
end
