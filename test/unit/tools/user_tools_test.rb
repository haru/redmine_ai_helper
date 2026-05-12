require File.expand_path("../../../test_helper", __FILE__)

class UserToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :custom_values, :groups_users, :members, :member_roles, :roles, :user_preferences
  include RedmineAiHelper::Tools

  context "UserTools" do
    setup do
      @provider = UserTools.new
      @users = User.where(status: User::STATUS_ACTIVE)
    end

    context "list users" do
      should "success by default" do
        result = @provider.list_users

        assert_equal @users.count, result[:total]
        assert_equal @users.map(&:id).sort, result[:users].map { |u| u[:id] }.sort
      end

      should "success with limit" do
        result = @provider.list_users(query: { limit: 5 })

        assert_equal 5, result[:users].size
      end

      should "success with status" do
        locked = User.where(status: User::STATUS_LOCKED)
        result = @provider.list_users(query: { status: "locked" })

        assert_equal locked.count, result[:users].size
      end

      should "success with date fields" do
        2.times { |i| @users[i].last_login_on = (i + 1).days.ago; @users[i].save! }
        result = @provider.list_users(query: { date_fields: [ { field_name: "last_login_on", operator: ">=", value: 1.year.ago.to_s } ] })

        assert_equal 2, result[:users].size

        @users.update_all(last_login_on: 1.day.ago)
        3.times { |i| @users[i].update_attribute(:last_login_on, (i + 2).years.ago) }
        @users[4].last_login_on = nil
        @users.each { |u| u.save! }
        result = @provider.list_users(query: { date_fields: [ { field_name: "last_login_on", operator: "<=", value: 1.year.ago.to_s } ] })

        assert_equal 4, result[:users].size
      end

      should "success with sort" do
        result = @provider.list_users(query: { sort: { field_name: "created_on", order: "asc" } })

        assert_equal(@users.order(:created_on).map(&:id), result[:users].map { |u| u[:id] })
      end

      should "handle string-key query from RubyLLM" do
        result = @provider.list_users(query: { "limit" => 3, "sort" => { "field_name" => "created_on", "order" => "asc" } })

        assert_equal 3, result[:users].size
        assert_equal(@users.order(:created_on).limit(3).map(&:id), result[:users].map { |u| u[:id] })
      end

      should "handle string-key date_fields from RubyLLM" do
        @users.update_all(last_login_on: 1.day.ago)
        result = @provider.list_users(query: { "date_fields" => [ { "field_name" => "last_login_on", "operator" => ">=", "value" => 1.year.ago.to_s } ] })

        assert_operator result[:users].size, :>, 0
      end
    end

    context "find user" do
      should "find user by name" do
        result = @provider.find_user(name: "admin")

        assert_equal 1, result[:users].size
        assert_equal "admin", result[:users].first[:login]
      end

      should "find user by login" do
        result = @provider.find_user(name: "admin")

        assert_equal 1, result[:users].size
        assert_equal "admin", result[:users].first[:login]
      end

      should "return error if name is not provided" do
        assert_raises(ArgumentError) do
          @provider.find_user()
        end
      end
    end
  end
end
