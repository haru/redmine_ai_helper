require File.expand_path("../../../test_helper", __FILE__)

class IssueSearchToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields,
           :enabled_modules, :roles, :members, :member_roles

  def setup
    @provider = RedmineAiHelper::Tools::IssueSearchTools.new
    # search_issues requires the ai_helper module and the view_ai_helper permission
    # on the searched project. Project 1 with role 1 (jsmith's role) is the baseline
    # used by every search test below.
    EnabledModule.create!(project_id: 1, name: "ai_helper")
    Role.find(1).add_permission!(:view_ai_helper)
  end

  context "search_issues" do
    setup do
      @project = Project.find(1)
      @tracker = Tracker.find(1)
      @user = User.find(2)
      @previous_user = User.current
      User.current = @user
    end

    teardown do
      User.current = @previous_user
    end

    should "return issues matching search conditions" do
      result = @provider.search_issues(project_id: @project.id, fields: [
        { field_name: "tracker_id", operator: "=", values: [ @tracker.id.to_s ] }
      ])

      assert result.key?(:issues)
      assert result.key?(:total_count)
      assert_kind_of Array, result[:issues]
      assert_kind_of Integer, result[:total_count]
    end

    should "return issues when no filters specified" do
      result = @provider.search_issues(project_id: @project.id)

      assert result.key?(:issues)
      assert result.key?(:total_count)
      assert_kind_of Array, result[:issues]
    end

    should "limit results to 50 issues" do
      # Create more than 50 issues
      55.times do |i|
        Issue.create!(
          project: @project,
          tracker: @tracker,
          subject: "Test Issue #{i}",
          author: @user,
          status: IssueStatus.first,
          priority: IssuePriority.first
        )
      end

      result = @provider.search_issues(project_id: @project.id)

      assert_operator result[:issues].length, :<=, 50
      assert_operator result[:total_count], :>=, 55
    end

    should "refuse to search a project that is not visible to the current user" do
      # Create a private project with a new tracker
      private_tracker = Tracker.create!(name: "PrivateTracker#{Time.now.to_i}#{rand(10000)}", default_status: IssueStatus.first)
      private_project = Project.create!(
        name: "Private Test",
        identifier: "private-test-#{Time.now.to_i}-#{rand(10000)}",
        is_public: false
      )
      # Avoid adding the same tracker twice to prevent uniqueness violations on the join table
      unless private_project.trackers.include?(private_tracker)
        private_project.trackers << private_tracker
      end
      # Enable the module so that a disabled module cannot be the reason for the failure
      EnabledModule.create!(project_id: private_project.id, name: "ai_helper")

      Issue.create!(
        project: private_project,
        tracker: private_tracker,
        subject: "Private Issue",
        author: @user,
        status: IssueStatus.first,
        priority: IssuePriority.first
      )

      # Switch to anonymous user
      User.current = User.anonymous

      assert_raises(RuntimeError) do
        @provider.search_issues(project_id: private_project.id)
      end
    ensure
      private_project&.destroy
      private_tracker&.destroy
    end

    should "exclude issues the current user cannot see inside an accessible project" do
      # "default" visibility hides private issues from anyone but their author and assignee
      Role.find(1).update!(issues_visibility: "default")
      private_issue = Issue.create!(
        project: @project, tracker: @tracker, subject: "Private Issue In Accessible Project",
        author: User.find(3), status: IssueStatus.first, priority: IssuePriority.first,
        is_private: true
      )
      visible_issue = Issue.create!(
        project: @project, tracker: @tracker, subject: "Visible Issue In Accessible Project",
        author: User.find(3), status: IssueStatus.first, priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: @project.id)
      ids = result[:issues].map { |i| i[:id] }

      assert_includes ids, visible_issue.id
      assert_not_includes ids, private_issue.id
    ensure
      private_issue&.destroy
      visible_issue&.destroy
    end

    should "return formatted issue data with id and name" do
      issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        subject: "Formatted Test Issue",
        author: @user,
        status: IssueStatus.first,
        priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: @project.id)
      issue_data = result[:issues].find { |i| i[:id] == issue.id }

      assert_not_nil issue_data
      assert_equal "Formatted Test Issue", issue_data[:subject]
      # status should have id and name
      assert_equal issue.status.id, issue_data[:status][:id]
      assert_equal issue.status.name, issue_data[:status][:name]
      # priority should have id and name
      assert_equal issue.priority.id, issue_data[:priority][:id]
      assert_equal issue.priority.name, issue_data[:priority][:name]
      # tracker should have id and name
      assert_equal issue.tracker.id, issue_data[:tracker][:id]
      assert_equal issue.tracker.name, issue_data[:tracker][:name]
      # author should have id and name
      assert_equal issue.author.id, issue_data[:author][:id]
      assert_equal issue.author.name, issue_data[:author][:name]
    ensure
      issue&.destroy
    end

    should "handle string keys in nested hashes from RubyLLM" do
      result = @provider.search_issues(
        project_id: @project.id,
        fields: [ { "field_name" => "tracker_id", "operator" => "=", "values" => [ @tracker.id.to_s ] } ]
      )

      assert result.key?(:issues)
      assert(result[:issues].all? { |i| i[:tracker][:id] == @tracker.id })
    end

    should "handle string keys in date_fields from RubyLLM" do
      result = @provider.search_issues(
        project_id: @project.id,
        date_fields: [ { "field_name" => "due_date", "operator" => "!*", "values" => [] } ]
      )

      assert result.key?(:issues)
    end

    should "accept ><t+ relative date range operator with values" do
      result = @provider.search_issues(
        project_id: @project.id,
        date_fields: [ { field_name: "due_date", operator: "><t+", values: [ "1", "7" ] } ]
      )

      assert result.key?(:issues)
    end

    should "accept ><t- relative date range operator with values" do
      result = @provider.search_issues(
        project_id: @project.id,
        date_fields: [ { field_name: "due_date", operator: "><t-", values: [ "1", "7" ] } ]
      )

      assert result.key?(:issues)
    end

    should "filter issues by tracker condition" do
      # Get issues with specific tracker
      result = @provider.search_issues(
        project_id: @project.id,
        fields: [ { field_name: "tracker_id", operator: "=", values: [ @tracker.id.to_s ] } ]
      )

      # Verify all returned issues have the specified tracker
      assert_operator result[:issues].length, :>, 0, "Should return at least one issue"
      assert result[:issues].all? { |i| i[:tracker][:id] == @tracker.id },
             "All returned issues should have tracker_id #{@tracker.id}"
    end

    should "respect custom limit parameter" do
      # Create 10 issues
      10.times do |i|
        Issue.create!(
          project: @project,
          tracker: @tracker,
          subject: "Limit Test Issue #{i}",
          author: @user,
          status: IssueStatus.first,
          priority: IssuePriority.first
        )
      end

      result = @provider.search_issues(project_id: @project.id, limit: 5)

      assert_operator result[:issues].length, :<=, 5
      assert_operator result[:total_count], :>=, 10
    end

    should "respect custom limit parameter with filters" do
      # Create 10 issues
      10.times do |i|
        Issue.create!(
          project: @project,
          tracker: @tracker,
          subject: "Limit Filter Test Issue #{i}",
          author: @user,
          status: IssueStatus.first,
          priority: IssuePriority.first
        )
      end

      result = @provider.search_issues(
        project_id: @project.id,
        limit: 3,
        fields: [ { field_name: "tracker_id", operator: "=", values: [ @tracker.id.to_s ] } ]
      )

      assert_operator result[:issues].length, :<=, 3
      assert_operator result[:total_count], :>=, 10
    end

    should "return custom fields in correct format" do
      # Find a project with custom fields enabled
      issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        subject: "Issue with custom fields",
        author: @user,
        status: IssueStatus.first,
        priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: @project.id)
      issue_data = result[:issues].find { |i| i[:id] == issue.id }

      assert_not_nil issue_data
      assert_kind_of Array, issue_data[:custom_fields]
    ensure
      issue&.destroy
    end
  end

  context "search_issues access control" do
    setup do
      @project = Project.find(1)
      @tracker = Tracker.find(1)
      @user = User.find(2)
      @previous_user = User.current
      User.current = @user
    end

    teardown do
      User.current = @previous_user
    end

    context "when the ai_helper module is disabled" do
      setup do
        EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all
      end

      should "raise an error without search conditions" do
        assert_raises(RuntimeError) do
          @provider.search_issues(project_id: @project.id)
        end
      end

      should "raise an error with filter conditions as well" do
        assert_raises(RuntimeError) do
          @provider.search_issues(project_id: @project.id, fields: [
            { field_name: "tracker_id", operator: "=", values: [ @tracker.id.to_s ] }
          ])
        end
      end

      should "report the same error message as the other tools" do
        error = assert_raises(RuntimeError) do
          @provider.search_issues(project_id: @project.id)
        end

        assert_equal "ai_helper is not enabled for project: id = #{@project.id}", error.message
      end
    end

    should "raise an error when the user lacks the view_ai_helper permission" do
      Role.find(1).remove_permission!(:view_ai_helper)

      assert_raises(RuntimeError) do
        @provider.search_issues(project_id: @project.id)
      end
    end

    should "not raise when project_id is omitted" do
      assert_nothing_raised do
        @provider.search_issues(project_id: nil)
      end
    end

    should "raise a record not found error for a project that does not exist" do
      assert_raises(ActiveRecord::RecordNotFound) do
        @provider.search_issues(project_id: 0)
      end
    end

    should "state in the tool description that only ai_helper enabled projects are searchable" do
      schema = RedmineAiHelper::Tools::IssueSearchTools.function_schemas.to_openai_format.find do |f|
        f[:function][:name].end_with?("__search_issues")
      end

      assert_match(/AI Helper module enabled/, schema[:function][:description])
      assert_match(/AI Helper module enabled/, schema[:function][:parameters][:properties][:project_id][:description])
    end

    # T015
    should "state in the tool description that omitting project_id searches across accessible ai_helper enabled projects" do
      schema = RedmineAiHelper::Tools::IssueSearchTools.function_schemas.to_openai_format.find do |f|
        f[:function][:name].end_with?("__search_issues")
      end

      assert_match(/omit/i, schema[:function][:description])
      assert_match(/omit/i, schema[:function][:parameters][:properties][:project_id][:description])
    end
  end

  context "search_issues sort" do
    setup do
      @project = Project.find(1)
      @tracker = Tracker.find(1)
      @other_tracker = Tracker.find(2)
      @user = User.find(2)
      @previous_user = User.current
      User.current = @user

      # due_date/start_date/done_ratio must be set at creation time: update_column silently
      # no-ops for these attributes (Issue overrides their accessors), so it can't be used to
      # backfill them after the fact.
      @issue_a = Issue.create!(
        project: @project, tracker: @tracker, subject: "Sort Issue A",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first,
        start_date: Date.current - 3, due_date: Date.current + 1, done_ratio: 0
      )
      @issue_b = Issue.create!(
        project: @project, tracker: @tracker, subject: "Sort Issue B",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first,
        start_date: Date.current - 2, due_date: Date.current + 2, done_ratio: 40
      )
      @issue_c = Issue.create!(
        project: @project, tracker: @other_tracker, subject: "Sort Issue C",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first,
        start_date: Date.current - 1, due_date: Date.current + 3, done_ratio: 80
      )

      # Issue#create! bumps lock_version via an internal callback save without syncing the
      # in-memory attribute, so update_column's optimistic-locking WHERE clause matches 0 rows
      # and silently no-ops (mysql2/postgresql) unless we reload to pick up the real lock_version.
      [ @issue_a, @issue_b, @issue_c ].each(&:reload)

      # Force a deterministic A < B < C ordering for created_on/updated_on too.
      # id already ascends A < B < C by creation order.
      base_time = Time.current
      @issue_a.update_column(:created_on, base_time - 3.hours)
      @issue_a.update_column(:updated_on, base_time - 3.hours)
      @issue_b.update_column(:created_on, base_time - 2.hours)
      @issue_b.update_column(:updated_on, base_time - 2.hours)
      @issue_c.update_column(:created_on, base_time - 1.hour)
      @issue_c.update_column(:updated_on, base_time - 1.hour)
    end

    teardown do
      User.current = @previous_user
      [ @issue_a, @issue_b, @issue_c ].each { |i| i&.destroy }
    end

    # C1
    should "default to id descending order without error when sort is omitted" do
      result = @provider.search_issues(project_id: @project.id)

      ids = result[:issues].map { |i| i[:id] }
      assert_equal ids.sort.reverse, ids
    end

    # C2
    should "sort by created_on descending when direction is omitted" do
      result = @provider.search_issues(project_id: @project.id, sort: { field: "created_on" })

      our_ids = result[:issues].map { |i| i[:id] }.select { |id| [ @issue_a.id, @issue_b.id, @issue_c.id ].include?(id) }
      assert_equal [ @issue_c.id, @issue_b.id, @issue_a.id ], our_ids
    end

    # C3
    should "sort by updated_on ascending when direction is asc" do
      result = @provider.search_issues(project_id: @project.id, sort: { field: "updated_on", direction: "asc" })

      our_ids = result[:issues].map { |i| i[:id] }.select { |id| [ @issue_a.id, @issue_b.id, @issue_c.id ].include?(id) }
      assert_equal [ @issue_a.id, @issue_b.id, @issue_c.id ], our_ids
    end

    # C4
    should "apply sort to filtered results without breaking limit or visibility" do
      # Make updated_on intentionally *not* correlate with id: the older issue (A) gets the
      # newer updated_on. This way a "updated_on desc" result of [A, B] can only happen if the
      # sort is actually applied in the filtered/query-builder path; if sort were ignored it would
      # fall back to id desc and yield [B, A], failing the assertion below.
      now = Time.current
      @issue_a.update_column(:updated_on, now)
      @issue_b.update_column(:updated_on, now - 1.hour)

      result = @provider.search_issues(
        project_id: @project.id,
        fields: [ { field_name: "tracker_id", operator: "=", values: [ @tracker.id.to_s ] } ],
        sort: { field: "updated_on", direction: "desc" }
      )

      returned_ids = result[:issues].map { |i| i[:id] }
      assert_includes returned_ids, @issue_a.id
      assert_includes returned_ids, @issue_b.id
      assert_not_includes returned_ids, @issue_c.id, "issue with a different tracker must not be included"

      our_ids = returned_ids.select { |id| [ @issue_a.id, @issue_b.id ].include?(id) }
      assert_equal [ @issue_a.id, @issue_b.id ], our_ids
    end

    # C8
    RedmineAiHelper::Tools::IssueSearchTools::SUPPORTED_SORT_FIELDS.each do |sort_field|
      should "sort by #{sort_field} ascending and descending" do
        asc_result = @provider.search_issues(project_id: @project.id, sort: { field: sort_field, direction: "asc" })
        asc_ids = asc_result[:issues].map { |i| i[:id] }.select { |id| [ @issue_a.id, @issue_b.id, @issue_c.id ].include?(id) }
        assert_equal [ @issue_a.id, @issue_b.id, @issue_c.id ], asc_ids

        desc_result = @provider.search_issues(project_id: @project.id, sort: { field: sort_field, direction: "desc" })
        desc_ids = desc_result[:issues].map { |i| i[:id] }.select { |id| [ @issue_a.id, @issue_b.id, @issue_c.id ].include?(id) }
        assert_equal [ @issue_c.id, @issue_b.id, @issue_a.id ], desc_ids
      end
    end

    # C5
    should "raise a clear error listing supported fields when field is unsupported" do
      error = assert_raises(RuntimeError) do
        @provider.search_issues(project_id: @project.id, sort: { field: "assigned_to" })
      end

      assert_match(/assigned_to/, error.message)
      %w[id created_on updated_on due_date start_date done_ratio].each do |field|
        assert_match(/#{field}/, error.message)
      end
    end

    # C6
    should "raise a clear error when field is missing from sort" do
      error = assert_raises(RuntimeError) do
        @provider.search_issues(project_id: @project.id, sort: { direction: "asc" })
      end

      assert_match(/field/i, error.message)
    end

    # C7
    should "raise a clear error when direction is invalid" do
      error = assert_raises(RuntimeError) do
        @provider.search_issues(project_id: @project.id, sort: { field: "id", direction: "sideways" })
      end

      assert_match(/asc/i, error.message)
      assert_match(/desc/i, error.message)
    end
  end

  context "search_issues cross-project (project_id omitted)" do
    setup do
      @project1 = Project.find(1)
      @project2 = Project.find(2)
      @tracker = Tracker.find(1)
      @other_tracker = Tracker.find(2)
      @user = User.find(2)
      @previous_user = User.current
      User.current = @user

      # jsmith (user 2) holds role 1 on project 1 (view_ai_helper granted in top-level setup)
      # and role 2 on project 2; grant the same permission there for a second accessible project.
      EnabledModule.create!(project_id: 2, name: "ai_helper")
      Role.find(2).add_permission!(:view_ai_helper)
    end

    teardown do
      User.current = @previous_user
    end

    # T003
    should "return issues from multiple ai_helper enabled projects when project_id is omitted" do
      issue1 = Issue.create!(project: @project1, tracker: @tracker, subject: "Cross Project Issue 1",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      issue2 = Issue.create!(project: @project2, tracker: @tracker, subject: "Cross Project Issue 2",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)

      result = @provider.search_issues(project_id: nil)
      ids = result[:issues].map { |i| i[:id] }

      assert_includes ids, issue1.id
      assert_includes ids, issue2.id
    ensure
      issue1&.destroy
      issue2&.destroy
    end

    # T004
    should "return only matching issues across multiple projects when a filter is applied and project_id is omitted" do
      matching1 = Issue.create!(project: @project1, tracker: @tracker, subject: "Matching In Project 1",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      matching2 = Issue.create!(project: @project2, tracker: @tracker, subject: "Matching In Project 2",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      non_matching = Issue.create!(project: @project2, tracker: @other_tracker, subject: "Non Matching Tracker",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)

      result = @provider.search_issues(
        project_id: nil,
        fields: [ { field_name: "tracker_id", operator: "=", values: [ @tracker.id.to_s ] } ]
      )
      ids = result[:issues].map { |i| i[:id] }

      assert_includes ids, matching1.id
      assert_includes ids, matching2.id
      assert_not_includes ids, non_matching.id
      assert_operator result[:total_count], :>=, 2
    ensure
      matching1&.destroy
      matching2&.destroy
      non_matching&.destroy
    end

    # T009
    should "exclude issues from a project the user cannot view when project_id is omitted" do
      private_tracker = Tracker.create!(name: "PrivateTracker#{Time.now.to_i}#{rand(10000)}", default_status: IssueStatus.first)
      private_project = Project.create!(
        name: "Cross Private Test",
        identifier: "cross-private-test-#{Time.now.to_i}#{rand(10000)}",
        is_public: false
      )
      private_project.trackers << private_tracker unless private_project.trackers.include?(private_tracker)
      EnabledModule.create!(project_id: private_project.id, name: "ai_helper")

      hidden_issue = Issue.create!(
        project: private_project, tracker: private_tracker, subject: "Hidden From Cross Search",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: nil)
      ids = result[:issues].map { |i| i[:id] }

      assert_not_includes ids, hidden_issue.id
    ensure
      hidden_issue&.destroy
      private_project&.destroy
      private_tracker&.destroy
    end

    # T010
    should "exclude issues from a viewable project whose ai_helper module is disabled when project_id is omitted" do
      plain_tracker = Tracker.create!(name: "PlainTracker#{Time.now.to_i}#{rand(10000)}", default_status: IssueStatus.first)
      plain_project = Project.create!(
        name: "Cross No Module Test",
        identifier: "cross-no-module-test-#{Time.now.to_i}#{rand(10000)}",
        is_public: true
      )
      plain_project.trackers << plain_tracker unless plain_project.trackers.include?(plain_tracker)
      # Deliberately do not enable the ai_helper module for this project.

      excluded_issue = Issue.create!(
        project: plain_project, tracker: plain_tracker, subject: "Excluded No Module Issue",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: nil)
      ids = result[:issues].map { |i| i[:id] }

      assert_not_includes ids, excluded_issue.id
    ensure
      excluded_issue&.destroy
      plain_project&.destroy
      plain_tracker&.destroy
    end

    # T011
    should "return an empty result without error when no project is accessible via ai_helper" do
      Role.find(1).remove_permission!(:view_ai_helper)
      Role.find(2).remove_permission!(:view_ai_helper)

      result = @provider.search_issues(project_id: nil)

      assert_equal [], result[:issues]
      assert_equal 0, result[:total_count]
    end

    # T013
    should "apply sort and limit across multiple projects when project_id is omitted" do
      now = Time.current
      issue_old = Issue.create!(project: @project1, tracker: @tracker, subject: "Cross Sort Old",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      issue_mid = Issue.create!(project: @project2, tracker: @tracker, subject: "Cross Sort Mid",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      issue_new = Issue.create!(project: @project1, tracker: @tracker, subject: "Cross Sort New",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      [ issue_old, issue_mid, issue_new ].each(&:reload)
      issue_old.update_column(:created_on, now - 3.hours)
      issue_mid.update_column(:created_on, now - 2.hours)
      issue_new.update_column(:created_on, now - 1.hour)

      result = @provider.search_issues(project_id: nil, sort: { field: "created_on", direction: "desc" }, limit: 2)
      ids = result[:issues].map { |i| i[:id] }
      our_ids = ids.select { |id| [ issue_old.id, issue_mid.id, issue_new.id ].include?(id) }

      assert_equal [ issue_new.id, issue_mid.id ], our_ids
      assert_operator result[:issues].length, :<=, 2
    ensure
      issue_old&.destroy
      issue_mid&.destroy
      issue_new&.destroy
    end

    # T014
    should "apply a custom_fields filter across multiple projects, excluding issues whose tracker lacks that field" do
      cf = CustomField.find(1) # "Database" custom field, associated only with tracker 1
      tracker_without_cf = Tracker.create!(name: "NoCFTracker#{Time.now.to_i}#{rand(10000)}", default_status: IssueStatus.first)
      @project2.trackers << tracker_without_cf unless @project2.trackers.include?(tracker_without_cf)

      matching_issue = Issue.create!(
        project: @project1, tracker: @tracker, subject: "Has Database CF",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first,
        custom_field_values: { cf.id => "MySQL" }
      )

      non_matching_issue = Issue.create!(
        project: @project2, tracker: tracker_without_cf, subject: "No Database CF",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first
      )

      result = @provider.search_issues(
        project_id: nil,
        custom_fields: [ { field_id: cf.id, operator: "=", values: [ "MySQL" ] } ]
      )
      ids = result[:issues].map { |i| i[:id] }

      assert_includes ids, matching_issue.id
      assert_not_includes ids, non_matching_issue.id
      assert_operator result[:total_count], :>=, 1
    ensure
      matching_issue&.destroy
      non_matching_issue&.destroy
      tracker_without_cf&.destroy
    end
  end

  context "search_issues response includes project and hours fields" do
    setup do
      @project = Project.find(1)
      @tracker = Tracker.find(1)
      @user = User.find(2)
      @previous_user = User.current
      User.current = @user
    end

    teardown do
      User.current = @previous_user
    end

    should "include project with id and name in each issue" do
      result = @provider.search_issues(project_id: @project.id)

      assert result[:issues].all? { |i| i.key?(:project) && i[:project][:id] && i[:project][:name] },
             "Every issue must include a project hash with id and name"
    end

    should "include estimated_hours in each issue" do
      result = @provider.search_issues(project_id: @project.id)

      assert result[:issues].all? { |i| i.key?(:estimated_hours) },
             "Every issue must include estimated_hours"
    end

    should "include total_estimated_hours, spent_hours, and total_spent_hours in each issue" do
      result = @provider.search_issues(project_id: @project.id)

      assert result[:issues].all? { |i| i.key?(:total_estimated_hours) },
             "Every issue must include total_estimated_hours"
      assert result[:issues].all? { |i| i.key?(:spent_hours) },
             "Every issue must include spent_hours"
      assert result[:issues].all? { |i| i.key?(:total_spent_hours) },
             "Every issue must include total_spent_hours"
    end

    should "return nil or zero values for hours when issue has no time estimates or entries" do
      issue = Issue.create!(
        project: @project, tracker: @tracker, subject: "No Hours Issue",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: @project.id)
      issue_data = result[:issues].find { |i| i[:id] == issue.id }

      assert_not_nil issue_data
      assert_nil issue_data[:estimated_hours]
      assert_includes [ nil, 0, 0.0 ], issue_data[:total_estimated_hours]
      assert_includes [ 0, 0.0 ], issue_data[:spent_hours]
      assert_includes [ 0, 0.0 ], issue_data[:total_spent_hours]
    ensure
      issue&.destroy
    end

    should "return correct project for each issue when searching across multiple projects" do
      project2 = Project.find(2)
      EnabledModule.create!(project_id: project2.id, name: "ai_helper")
      Role.find(2).add_permission!(:view_ai_helper)

      issue1 = Issue.create!(project: @project, tracker: @tracker, subject: "Multi Project A",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      issue2 = Issue.create!(project: project2, tracker: @tracker, subject: "Multi Project B",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first)

      result = @provider.search_issues(project_id: nil)
      data_a = result[:issues].find { |i| i[:id] == issue1.id }
      data_b = result[:issues].find { |i| i[:id] == issue2.id }

      assert_not_nil data_a
      assert_equal @project.id, data_a[:project][:id]
      assert_equal @project.name, data_a[:project][:name]

      assert_not_nil data_b
      assert_equal project2.id, data_b[:project][:id]
      assert_equal project2.name, data_b[:project][:name]
    ensure
      issue1&.destroy
      issue2&.destroy
    end
  end

  context "validate_search_params" do
    # T003
    context "when fields is nil" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, nil, [])
        end
      end

      should "return empty errors array" do
        errors = @provider.send(:validate_search_params, nil, [])

        assert_equal [], errors
      end
    end

    # T004
    context "when date_fields is nil" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [], nil)
        end
      end

      should "return empty errors array" do
        errors = @provider.send(:validate_search_params, [], nil)

        assert_equal [], errors
      end
    end

    # T005
    context "when field_name is nil in fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params,
            [ { field_name: nil, operator: "=", values: [ "1" ] } ], [])
        end
      end

      should "add an error message mentioning field_name" do
        errors = @provider.send(:validate_search_params,
          [ { field_name: nil, operator: "=", values: [ "1" ] } ], [])

        assert errors.any? { |e| e.include?("field_name") },
          "Expected error message to mention field_name, got: #{errors.inspect}"
      end
    end

    # T006
    context "when values is nil in fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params,
            [ { field_name: "tracker_id", operator: "=", values: nil } ], [])
        end
      end

      should "add an error message mentioning values" do
        errors = @provider.send(:validate_search_params,
          [ { field_name: "tracker_id", operator: "=", values: nil } ], [])

        assert errors.any? { |e| e.include?("values") },
          "Expected error message to mention values, got: #{errors.inspect}"
      end
    end

    # T007
    context "when field_name is nil in date_fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [],
            [ { field_name: nil, operator: "=", values: [ "2024-01-01" ] } ])
        end
      end

      should "add an error message mentioning field_name" do
        errors = @provider.send(:validate_search_params, [],
          [ { field_name: nil, operator: "=", values: [ "2024-01-01" ] } ])

        assert errors.any? { |e| e.include?("field_name") },
          "Expected error message to mention field_name, got: #{errors.inspect}"
      end
    end

    # T008
    context "when values is nil in date_fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [],
            [ { field_name: "due_date", operator: "=", values: nil } ])
        end
      end

      should "add an error message mentioning values" do
        errors = @provider.send(:validate_search_params, [],
          [ { field_name: "due_date", operator: "=", values: nil } ])

        assert errors.any? { |e| e.include?("values") },
          "Expected error message to mention values, got: #{errors.inspect}"
      end
    end

    # T009
    context "when a value element is nil in date_fields values" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [],
            [ { field_name: "due_date", operator: "=", values: [ nil, "2024-01-01" ] } ])
        end
      end

      should "add an error message for the nil value" do
        errors = @provider.send(:validate_search_params, [],
          [ { field_name: "due_date", operator: "=", values: [ nil, "2024-01-01" ] } ])

        assert_predicate errors, :any?,
          "Expected at least one error message, got empty array"
      end
    end

    # T010
    context "when nil and valid fields are mixed" do
      should "continue validating valid fields after encountering a nil field_name" do
        errors = @provider.send(:validate_search_params, [
          { field_name: nil, operator: "=", values: [ "1" ] },
          { field_name: "tracker_id", operator: "=", values: [ "not-a-number" ] }
        ], [])
        # Expect error from nil field_name AND error from invalid numeric value
        assert_operator errors.length, :>=, 2, "Expected at least 2 errors (nil field_name + invalid numeric), got: #{errors.inspect}"
      end

      should "continue validating date_fields after encountering a nil field" do
        errors = @provider.send(:validate_search_params, [],
          [
            { field_name: nil, operator: "=", values: [ "2024-01-01" ] },
            { field_name: "due_date", operator: "=", values: [ "not-a-date" ] }
          ])

        assert_operator errors.length, :>=, 2, "Expected at least 2 errors, got: #{errors.inspect}"
      end
    end

    # T014 / T015 - warn logging
    context "warn logging when field_name is nil" do
      should "call ai_helper_logger warn when field_name is nil in fields" do
        mock_logger = mock("logger")
        mock_logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(mock_logger)
        @provider.send(:validate_search_params,
          [ { field_name: nil, operator: "=", values: [ "1" ] } ], [])
      end
    end

    context "warn logging when values is nil" do
      should "call ai_helper_logger warn when values is nil in fields" do
        mock_logger = mock("logger")
        mock_logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(mock_logger)
        @provider.send(:validate_search_params,
          [ { field_name: "tracker_id", operator: "=", values: nil } ], [])
      end

      should "call ai_helper_logger warn when values is nil in date_fields" do
        mock_logger = mock("logger")
        mock_logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(mock_logger)
        @provider.send(:validate_search_params, [],
          [ { field_name: "due_date", operator: "=", values: nil } ])
      end
    end
  end
end
