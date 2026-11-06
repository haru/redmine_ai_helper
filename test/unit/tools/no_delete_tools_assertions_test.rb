# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require_relative "no_delete_tools_assertions"

# Pins the spellings that NoDeleteToolsAssertions::DESTRUCTIVE_CALL must catch
# (and a few it must leave alone), so the "no destructive call" tests of the
# project management tools cannot silently go blind (CRF-024, CRF-033).
class NoDeleteToolsAssertionsTest < ActiveSupport::TestCase
  CAUGHT = [
    "project.destroy",
    "project.destroy!",
    "Project.destroy_all",
    "member.delete",
    "scope.delete_all",
    "project.archive",
    "project.close",
    "project.reopen",
    "project.members.clear",
    "project.send(:destroy)",
    "project.public_send(:destroy)",
    "project.public_send(\"delete\")",
    "project.update(status: Project::STATUS_CLOSED)",
    "project.update!(status: 9)",
    "project.update_attribute(:status, 9)",
    "Project.update_all(status: 9)",
    "project.update_column(:status, 9)",
    "project.update_columns(status: 9)",
    "project.status = 9",
    "attrs = { status: Project::STATUS_ARCHIVED }"
  ].freeze

  IGNORED = [
    "project.update(name: \"x\")",
    "status: project.status,",
    "project.status == 1",
    "member.destroy_something_else_entirely_is_not_a_call"
  ].freeze

  should "catch every destructive spelling" do
    CAUGHT.each do |line|
      assert_match NoDeleteToolsAssertions::DESTRUCTIVE_CALL, line, "must catch: #{line}"
    end
  end

  should "leave harmless lines alone" do
    IGNORED.each do |line|
      assert_no_match NoDeleteToolsAssertions::DESTRUCTIVE_CALL, line, "must ignore: #{line}"
    end
  end
end
