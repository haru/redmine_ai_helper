# frozen_string_literal: true

require_relative "../test_helper"

class AiHelperJournalEditControlsTest < ActionController::TestCase
  tests JournalsController

  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories,
           :versions, :custom_fields, :custom_values, :groups_users, :members, :member_roles, :roles,
           :user_preferences, :wikis, :wiki_pages, :wiki_contents, :enabled_modules, :journals

  def setup
    @controller = JournalsController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create
    @project = projects(:projects_001)
    @issue = issues(:issues_001)
    @journal = journals(:journals_002)
    User.current = nil

    enabled_module = EnabledModule.new
    enabled_module.project_id = @project.id
    enabled_module.name = "ai_helper"
    enabled_module.save!
  end

  def teardown
    User.current = nil
  end

  # Extracts the HTML fragment that journals/edit.js.erb inserts after the
  # notes span, JS-unescapes it, and parses it with Nokogiri.
  def inserted_notes_form_html(journal)
    body = @response.body
    marker = "$(\"#journal-#{journal.id}-notes\").after('"
    start = body.index(marker)
    body = body[(start + marker.length)..] if start
    closing = body.index("');")
    body = body[0...closing] if closing
    unescape_javascript_escapes(body)
  end

  # Inverse of Rails' escape_javascript: `\x` becomes the mapped character.
  def unescape_javascript_escapes(text)
    text.gsub(/\\(.)/m) do
      case Regexp.last_match(1)
      when "n" then "\n"
      when "r" then "\r"
      when "t" then "\t"
      else Regexp.last_match(1)
      end
    end
  end

  def edit_journal(journal, user: User.find(1))
    @request.session[:user_id] = user.id
    User.current = user
    get :edit, params: { id: journal.id }, xhr: true
    assert_response :success
    Nokogiri::HTML::DocumentFragment.parse(inserted_notes_form_html(journal))
  end

  test "edit form renders exactly one journal edit controls container with the checkbox, check button and control panel" do
    doc = edit_journal(@journal)

    controls = doc.css(".ai-helper-journal-edit-controls")
    assert_equal 1, controls.size, "expected exactly one .ai-helper-journal-edit-controls"

    assert controls.at_css("#ai-helper-journal-#{@journal.id}-autocompletion-toggle.ai-helper-journal-autocompletion-toggle"),
           "expected the autocompletion checkbox for journal #{@journal.id}"
    assert controls.at_css("a.ai-helper-journal-typo-check-btn"), "expected the typo check button"

    panel = controls.at_css(".ai-helper-journal-typo-control-panel")
    assert panel, "expected the typo control panel"
    assert panel.at_css("button.ai-helper-typo-apply-all-btn"), "expected the apply-all button"
    assert panel.at_css("button.ai-helper-typo-close-btn"), "expected the close button"

    assert controls.at_css("button.ai-helper-typo-accept-btn-template"), "expected the accept button template"
    assert controls.at_css("button.ai-helper-typo-reject-btn-template"), "expected the reject button template"
  end

  test "edit form controls render hidden and carry the data-config from the contract" do
    doc = edit_journal(@journal)

    controls = doc.at_css(".ai-helper-journal-edit-controls")
    assert_equal "display: none;", controls["style"], "expected the controls container to start hidden"

    panel = controls.at_css(".ai-helper-journal-typo-control-panel")
    assert_equal "display: none;", panel["style"], "expected the control panel to start hidden"

    config = JSON.parse(controls["data-config"])
    assert_equal @journal.id, config["journalId"]
    assert_equal "journal_#{@journal.id}_notes", config["textareaId"]
    assert_equal "/projects/#{@project.id}/ai_helper/issue/#{@issue.id}/suggest_completion", config["completionEndpoint"]
    assert_equal "/projects/#{@project.identifier}/ai_helper/check_typos", config["typoEndpoint"]
    assert_equal User.current.id, config["userId"]

    completion_labels = config["completionLabels"]
    assert_equal I18n.t("ai_helper.autocompletion.note_enabled_tooltip"), completion_labels["enabledTooltip"]
    assert_equal I18n.t("ai_helper.autocompletion.note_disabled_tooltip"), completion_labels["disabledTooltip"]
    %w[commonToggleLabel loading noSuggestions acceptSuggestion dismiss].each do |key|
      assert completion_labels.key?(key), "expected completionLabels to contain #{key}"
    end

    typo_labels = config["typoLabels"]
    %w[suggestionsTitle noSuggestions checkButton checking acceptSuggestion
       dismissSuggestion acceptAll dismissAll errorOccurred correctionTooltip applyFailed].each do |key|
      assert typo_labels.key?(key), "expected typoLabels to contain #{key}"
    end
  end

  test "edit form renders nothing when the ai_helper module is disabled" do
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all

    doc = edit_journal(@journal)

    assert_equal 0, doc.css(".ai-helper-journal-edit-controls").size
    assert_equal 0, doc.css(".ai-helper-autocompletion-controls").size
  end

  test "edit form renders the controls for a user with only edit_own_issue_notes (no edit_issues)" do
    role = Role.create!(name: "Own notes editor",
                        permissions: [ :view_issues, :edit_own_issue_notes, :view_ai_helper ])
    assert_not role.allowed_to?(edit_issues: 1), "the role must not carry :edit_issues"
    user = User.create!(login: "noteeditor", firstname: "Note", lastname: "Editor",
                        mail: "noteeditor@example.com", password: "abc12345", password_confirmation: "abc12345")
    Member.create!(project: @project, user: user, roles: [ role ])
    journal = Journal.create!(journalized: @issue, user: user, notes: "my own note")

    doc = edit_journal(journal, user: user)

    assert_equal 1, doc.css(".ai-helper-journal-edit-controls").size,
                 "expected the journal edit controls even without :edit_issues"
    assert doc.at_css(".ai-helper-journal-edit-controls #ai-helper-journal-#{journal.id}-autocompletion-toggle")
  end

  test "edit form renders the controls for a private note" do
    journal = Journal.create!(journalized: @issue, user: User.find(2),
                              notes: "private note", private_notes: true)

    doc = edit_journal(journal, user: User.find(1))

    assert_equal 1, doc.css(".ai-helper-journal-edit-controls").size,
                 "expected the journal edit controls for a visible private note"
  end
end
