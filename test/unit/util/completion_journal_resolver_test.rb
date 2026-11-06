# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/completion_journal_resolver"

class RedmineAiHelper::Util::CompletionJournalResolverTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :members, :member_roles,
           :roles, :journals, :enabled_modules, :projects_trackers

  Resolver = RedmineAiHelper::Util::CompletionJournalResolver

  setup do
    @issue = Issue.find(1)
    @journal = journals(:journals_002)
    @admin = User.find(1)
    @previous_user = User.current
    User.current = @admin
  end

  teardown do
    User.current = @previous_user
  end

  def error_message(key)
    I18n.t("ai_helper.completion_errors.#{key}")
  end

  context "CompletionJournalResolver.resolve" do
    should "return no journal and no error when journal_id is absent" do
      assert_equal [ nil, nil, nil ], Resolver.resolve({}, "note", @issue, @admin)
    end

    should "return no journal and no error when journal_id is null" do
      assert_equal [ nil, nil, nil ], Resolver.resolve({ "journal_id" => nil }, "note", @issue, @admin)
    end

    [ "42", 1.5, true, [ 1 ], { "a" => 1 } ].each do |bad|
      should "reject #{bad.inspect} as journal_id with bad_request" do
        result = Resolver.resolve({ "journal_id" => bad }, "note", @issue, @admin)
        assert_equal [ nil, error_message(:invalid_journal_id), :bad_request ], result
      end
    end

    should "reject a journal_id when the context type is not note" do
      result = Resolver.resolve({ "journal_id" => @journal.id }, "description", @issue, @admin)
      assert_equal [ nil, error_message(:journal_requires_note), :bad_request ], result
    end

    should "reject an unknown journal id" do
      result = Resolver.resolve({ "journal_id" => 999_999 }, "note", @issue, @admin)
      assert_equal [ nil, error_message(:journal_not_in_issue), :bad_request ], result
    end

    should "reject a journal that belongs to another issue" do
      result = Resolver.resolve({ "journal_id" => journals(:journals_003).id }, "note", @issue, @admin)
      assert_equal [ nil, error_message(:journal_not_in_issue), :bad_request ], result
    end

    should "reject a journal the user may see but not edit with forbidden" do
      role = Role.create!(name: "Resolver viewer", permissions: [ :view_issues ])
      viewer = User.create!(login: "resolverview", firstname: "Res", lastname: "Viewer",
                            mail: "resolverview@example.com", password: "abc12345", password_confirmation: "abc12345")
      Member.create!(project: @issue.project, user: viewer, roles: [ role ])

      result = Resolver.resolve({ "journal_id" => @journal.id }, "note", @issue, viewer)
      assert_equal [ nil, error_message(:journal_not_editable), :forbidden ], result
    end

    should "check visibility for the given user, not for User.current" do
      private_journal = Journal.create!(journalized: @issue, user: @admin, notes: "private note", private_notes: true)
      role = Role.create!(name: "Resolver private-blind", permissions: [ :view_issues, :edit_own_issue_notes ])
      viewer = User.create!(login: "resolverblind", firstname: "Res", lastname: "Blind",
                            mail: "resolverblind@example.com", password: "abc12345", password_confirmation: "abc12345")
      Member.create!(project: @issue.project, user: viewer, roles: [ role ])
      # User.current stays the admin, who can see private notes
      assert_equal @admin, User.current

      result = Resolver.resolve({ "journal_id" => private_journal.id }, "note", @issue, viewer)
      assert_equal [ nil, error_message(:journal_not_in_issue), :bad_request ], result
    end

    should "return the journal for an editable, visible journal of the issue" do
      journal, error, status = Resolver.resolve({ "journal_id" => @journal.id }, "note", @issue, @admin)
      assert_equal @journal, journal
      assert_nil error
      assert_nil status
    end
  end
end
