# frozen_string_literal: true

require_relative "../test_helper"

class ProjectsHelperPatchCompatibilityTest < ActiveSupport::TestCase
  should "render the core hierarchy without another patch" do
    helper = build_helper

    assert_equal "<p>Core hierarchy</p>", helper.render_project_hierarchy([])
    assert_equal [ :core ], helper.calls
  end

  should "preserve a hierarchy wrapper prepended before AI Helper" do
    helper = build_helper(other_patch_first: true)

    assert_equal "<section><p>Core hierarchy</p></section>", helper.render_project_hierarchy([])
    assert_equal [ :other, :core ], helper.calls
  end

  should "preserve a hierarchy wrapper prepended after AI Helper" do
    helper = build_helper(other_patch_first: false)

    assert_equal "<section><p>Core hierarchy</p></section>", helper.render_project_hierarchy([])
    assert_equal [ :other, :core ], helper.calls
  end

  private

  def build_helper(other_patch_first: nil)
    core = Module.new do
      def render_project_hierarchy(_projects)
        calls << :core
        "<p>Core hierarchy</p>"
      end
    end
    other_patch = Module.new do
      def render_project_hierarchy(projects)
        calls << :other
        "<section>#{super}</section>"
      end
    end
    core.prepend(other_patch) if other_patch_first == true
    # Reproduce the saved alias used by the old registration code. A cooperative
    # wrapper must follow super rather than this snapshot of the method chain.
    core.alias_method :render_project_hierarchy_without_ai_helper, :render_project_hierarchy
    core.prepend(RedmineAiHelper::ProjectsHelperPatch)
    core.prepend(other_patch) if other_patch_first == false

    Class.new do
      include core

      attr_reader :calls

      def initialize
        @calls = []
      end
    end.new
  end
end
