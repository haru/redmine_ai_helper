# frozen_string_literal: true

require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/project_write_guard"

module RedmineAiHelper
  module Tools
    # ProjectWriteTools provides write operations for Redmine projects:
    # creating projects, updating their basic attributes, and switching modules
    # and trackers on and off. Attributes that Redmine would silently discard
    # (publicity, member inheritance, modules, custom fields, parent) are checked
    # before assignment and rejected with an error instead (ADR-067).
    class ProjectWriteTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::ProjectWriteGuard

      define_function :create_project, write: true, description: "Create a project. Always confirm with the user before creating: show the name, the identifier, whether the project will be public or private, and the parent project first. The identifier cannot be changed after creation. Modules and trackers start with the Redmine defaults; the AI Helper module is enabled only when the creator may select modules. Non-admin creators become a member with the default role." do
        property :name, type: "string", description: "The project name.", required: true
        property :identifier, type: "string", description: "The project identifier (lowercase letters, numbers, dashes, underscores; up to 100 characters). Cannot be changed after creation.", required: true
        property :description, type: "string", description: "The project description.", required: false
        property :homepage, type: "string", description: "The project homepage URL.", required: false
        property :is_public, type: "boolean", description: "Whether the project is public. Omit for the Redmine default.", required: false
        property :parent_id, type: "integer", description: "The ID of the parent project to create a subproject.", required: false
        property :inherit_members, type: "boolean", description: "Whether to inherit members from the parent project.", required: false
        property :custom_fields, type: "array", description: "Values of the project custom fields. Use capable_project_props to see the editable ones and their possible values.", required: false do
          item type: "object", description: "A custom field value." do
            property :field_id, type: "integer", description: "The custom field ID.", required: true
            property :value, type: "string", description: "The value to set.", required: false
          end
        end
      end
      # Create a project. The creator becomes a member with the default role
      # (non-admin only), and the whole creation runs in one transaction (R-005).
      # @param name [String] The project name.
      # @param identifier [String] The project identifier.
      # @param description [String, nil] The description.
      # @param homepage [String, nil] The homepage URL.
      # @param is_public [Boolean, nil] The publicity (Redmine default when omitted).
      # @param parent_id [Integer, nil] The parent project ID.
      # @param inherit_members [Boolean, nil] The member inheritance flag.
      # @param custom_fields [Array<Hash>, nil] Custom field values ({ field_id:, value: }).
      # @return [Hash] The Project hash with ai_helper_module_enabled,
      #   ai_helper_accessible, and default_member_role, or { error: } for a
      #   user-caused failure.
      def create_project(name:, identifier:, description: nil, homepage: nil, is_public: nil,
                         parent_id: nil, inherit_members: nil, custom_fields: nil)
        user_errors_as_result do
          raise UserError, "name is required" if name.nil?
          raise UserError, "identifier is required" if identifier.nil?
          validate_booleans!("is_public" => is_public, "inherit_members" => inherit_members)

          validate_create_permission!(parent_id)
          if !User.current.admin? && Project.default_member_role.nil?
            raise UserError, "No role is configured for non-admin project creators"
          end

          custom_fields = normalize_custom_fields(custom_fields)
          project = Project.new(name: name, identifier: identifier, description: description, homepage: homepage)
          validate_custom_fields!(project, custom_fields)
          validate_publicity!(project, is_public)
          validate_inherit_members!(project, inherit_members)

          project.safe_attributes = build_project_attributes(
            is_public: is_public, parent_id: parent_id, inherit_members: inherit_members, custom_fields: custom_fields
          )
          # R-004: enable the ai_helper module only when the creator may select modules
          if project.safe_attribute?("enabled_module_names", User.current)
            project.enabled_module_names = project.enabled_module_names | [ "ai_helper" ]
          end

          ActiveRecord::Base.transaction do
            unless project.save
              raise UserError, "Failed to create project: #{project.errors.full_messages.join(", ")}"
            end
            unless User.current.admin?
              member = project.add_default_member(User.current)
              member.save!
            end
          end

          project_to_hash(project.reload).merge(
            ai_helper_module_enabled: project.module_enabled?(:ai_helper),
            ai_helper_accessible: accessible_project?(project),
            default_member_role: (User.current.admin? ? nil : format_named_record(Project.default_member_role))
          )
        end
      end

      define_function :update_modules, write: true, description: "Enable and disable project modules. Modules not mentioned stay as they are, and disabling a module does not delete its data. Always confirm with the user before disabling the ai_helper module: afterwards the AI may no longer be able to operate that project." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
        property :enable, type: "array", description: "The names of the modules to enable. Use capable_project_props to see the available names.", required: false do
          item type: "string"
        end
        property :disable, type: "array", description: "The names of the modules to disable.", required: false do
          item type: "string"
        end
      end
      # Enable and disable project modules. The new list is
      # (current names + enable) - disable; modules not mentioned stay as they are.
      # @param project_id [Integer] The project ID.
      # @param enable [Array<String>, nil] Module names to enable.
      # @param disable [Array<String>, nil] Module names to disable.
      # @return [Hash] The Project hash with unchanged:, or { error: } for a
      #   user-caused failure.
      def update_modules(project_id:, enable: nil, disable: nil)
        user_errors_as_result do
          project = writable_project!(project_id: project_id, permission: :select_project_modules)

          enable = validate_string_list!(enable, "enable")
          disable = validate_string_list!(disable, "disable")
          if enable.empty? && disable.empty?
            raise UserError, "enable or disable is required"
          end
          overlap = enable & disable
          if overlap.any?
            raise UserError, "The same module cannot be enabled and disabled: #{overlap.join(", ")}"
          end
          available = Redmine::AccessControl.available_project_modules.map(&:to_s)
          unknown = (enable + disable) - available
          unless unknown.empty?
            raise UserError, "Unknown modules: #{unknown.join(", ")}. Available modules: #{available.join(", ")}"
          end

          current = project.enabled_module_names
          new_names = (current | enable) - disable
          unchanged = ((enable & current) + (disable - current)).uniq
          next project_to_hash(project).merge(unchanged: unchanged.sort) if new_names.sort == current.sort

          # enabled_module_names= writes immediately, so assignment and save share a
          # transaction: a failed save must not leave the change behind.
          ActiveRecord::Base.transaction do
            project.enabled_module_names = new_names
            unless project.save
              raise UserError, "Failed to update modules: #{project.errors.full_messages.join(", ")}"
            end
          end
          project_to_hash(project.reload).merge(unchanged: unchanged.sort)
        end
      end

      define_function :update_project, write: true, description: "Update an existing project. Only the given attributes are changed; the identifier cannot be changed after creation. Pass an empty string to description or homepage to clear it. Always confirm with the user before making the project public: after the switch everyone can see the project (switching from public back to private needs no confirmation)." do
        property :project_id, type: "integer", description: "The ID of the project to update.", required: true
        property :name, type: "string", description: "The new project name.", required: false
        property :description, type: "string", description: "The new description. An empty string clears it.", required: false
        property :homepage, type: "string", description: "The new homepage URL. An empty string clears it.", required: false
        property :is_public, type: "boolean", description: "Whether the project is public. Requires the select_project_publicity permission.", required: false
        property :parent_id, type: "integer", description: "The ID of the new parent project. Cannot be combined with clear_parent.", required: false
        property :clear_parent, type: "boolean", description: "true makes the project a top-level project. Cannot be combined with parent_id.", required: false
        property :inherit_members, type: "boolean", description: "Whether to inherit members from the parent project. Requires the manage_members permission.", required: false
        property :custom_fields, type: "array", description: "Values of the project custom fields. Use capable_project_props to see the editable ones and their possible values.", required: false do
          item type: "object", description: "A custom field value." do
            property :field_id, type: "integer", description: "The custom field ID.", required: true
            property :value, type: "string", description: "The value to set.", required: false
          end
        end
      end
      # Update an existing project. Attributes that are nil are left unchanged.
      # @param project_id [Integer] The project ID.
      # @param name [String, nil] The new name.
      # @param description [String, nil] The new description ("" clears it).
      # @param homepage [String, nil] The new homepage ("" clears it).
      # @param is_public [Boolean, nil] The new publicity.
      # @param parent_id [Integer, nil] The new parent project ID.
      # @param clear_parent [Boolean, nil] true to make the project top-level.
      # @param inherit_members [Boolean, nil] The new member inheritance flag.
      # @param custom_fields [Array<Hash>, nil] Custom field values ({ field_id:, value: }).
      # @return [Hash] The Project hash, or { error: } for a user-caused failure.
      def update_project(project_id:, name: nil, description: nil, homepage: nil, is_public: nil,
                         parent_id: nil, clear_parent: nil, inherit_members: nil, custom_fields: nil)
        user_errors_as_result do
          project = writable_project!(project_id: project_id, permission: :edit_project)
          validate_booleans!("is_public" => is_public, "inherit_members" => inherit_members, "clear_parent" => clear_parent)
          if !parent_id.nil? && clear_parent == true
            raise UserError, "parent_id and clear_parent cannot be used together"
          end

          custom_fields = normalize_custom_fields(custom_fields)
          validate_custom_fields!(project, custom_fields)
          validate_publicity!(project, is_public)
          validate_inherit_members!(project, inherit_members)
          validate_parent!(project, parent_id, clear_parent)

          attrs = build_project_attributes(
            name: name, description: description, homepage: homepage, is_public: is_public,
            parent_id: parent_id, clear_parent: clear_parent, inherit_members: inherit_members,
            custom_fields: custom_fields
          )
          next project_to_hash(project) if attrs.empty?

          project.safe_attributes = attrs
          unless project.save
            raise UserError, "Failed to update project: #{project.errors.full_messages.join(", ")}"
          end
          project_to_hash(project.reload)
        end
      end

      define_function :add_trackers, write: true, description: "Assign trackers to a project (the issue_tracking module must be enabled). Trackers not mentioned stay as they are." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
        property :tracker_ids, type: "array", description: "The IDs of the trackers to assign. Use capable_project_props to see the trackers and their assigned flag.", required: true do
          item type: "integer"
        end
      end
      # Assign trackers to the project: new tracker_ids = current + given.
      # @param project_id [Integer] The project ID.
      # @param tracker_ids [Array<Integer>] The tracker IDs to assign (at least one).
      # @return [Hash] The Project hash with unchanged:, or { error: } for a
      #   user-caused failure.
      def add_trackers(project_id:, tracker_ids:)
        user_errors_as_result do
          project = writable_project!(project_id: project_id, permission: :edit_project, require_issue_tracking: true)
          tracker_ids = validate_tracker_ids!(tracker_ids)

          current = project.tracker_ids
          new_ids = current | tracker_ids
          unchanged = tracker_ids & current
          next tracker_result(project, unchanged, new_ids) if new_ids.sort == current.sort

          assign_trackers!(project, new_ids, "Failed to add trackers")
          tracker_result(project.reload, unchanged, new_ids)
        end
      end

      define_function :remove_trackers, write: true, description: "Unassign trackers from a project (the issue_tracking module must be enabled). Existing issues are not deleted and are not changed by this, and the trackers themselves are not modified. Trackers not mentioned stay assigned. When no tracker is left, the project can no longer create issues; tell the user about this." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
        property :tracker_ids, type: "array", description: "The IDs of the trackers to unassign.", required: true do
          item type: "integer"
        end
      end
      # Unassign trackers from the project: new tracker_ids = current - given.
      # @param project_id [Integer] The project ID.
      # @param tracker_ids [Array<Integer>] The tracker IDs to unassign (at least one).
      # @return [Hash] The Project hash with unchanged: and no_trackers (true when
      #   no tracker is left), or { error: } for a user-caused failure.
      def remove_trackers(project_id:, tracker_ids:)
        user_errors_as_result do
          project = writable_project!(project_id: project_id, permission: :edit_project, require_issue_tracking: true)
          tracker_ids = validate_tracker_ids!(tracker_ids)

          current = project.tracker_ids
          new_ids = current - tracker_ids
          unchanged = tracker_ids - current
          next tracker_result(project, unchanged, new_ids) if new_ids.sort == current.sort

          assign_trackers!(project, new_ids, "Failed to remove trackers")
          tracker_result(project.reload, unchanged, new_ids)
        end
      end

      private

      # Validate the tracker id list: an array of integers naming existing
      # trackers. One invalid id rejects the whole list.
      # @param tracker_ids [Object] The tracker IDs given by the caller.
      # @return [Array<Integer>] The validated tracker IDs without duplicates.
      # @raise [UserError] when the value is not an array of integers, the list is
      #   empty, or an id does not exist.
      def validate_tracker_ids!(tracker_ids)
        unless tracker_ids.is_a?(Array) && tracker_ids.all?(Integer)
          raise UserError, "tracker_ids must be an array of integers"
        end
        raise UserError, "tracker_ids is required (at least one tracker)" if tracker_ids.empty?

        missing = tracker_ids - Tracker.where(id: tracker_ids).pluck(:id)
        raise UserError, "Tracker not found: #{missing.join(", ")}" if missing.any?

        tracker_ids.uniq
      end

      # Validate an optional list of strings.
      # @param value [Object] The value given by the caller.
      # @param name [String] The argument name for the error message.
      # @return [Array<String>] The list (empty when nil).
      # @raise [UserError] when the value is neither nil nor an array of strings.
      def validate_string_list!(value, name)
        return [] if value.nil?
        raise UserError, "#{name} must be an array of strings" unless value.is_a?(Array) && value.all?(String)

        value.uniq
      end

      # Replace the tracker assignment. tracker_ids= writes the join table
      # immediately, so assignment and save share a transaction and a failed save
      # leaves nothing behind.
      # @param project [Project] The project.
      # @param tracker_ids [Array<Integer>] The new tracker IDs.
      # @param failure [String] The error message prefix when the save fails.
      # @return [void]
      # @raise [UserError] when the project cannot be saved.
      def assign_trackers!(project, tracker_ids, failure)
        ActiveRecord::Base.transaction do
          project.tracker_ids = tracker_ids
          raise UserError, "#{failure}: #{project.errors.full_messages.join(", ")}" unless project.save
        end
      end

      # The Project hash with unchanged: (and no_trackers when no tracker is left).
      # @param project [Project] The project.
      # @param unchanged [Array<Integer>] The tracker IDs that needed no change.
      # @param tracker_ids [Array<Integer>] The tracker IDs the project ends up with.
      # @return [Hash] The result hash.
      def tracker_result(project, unchanged, tracker_ids)
        result = project_to_hash(project).merge(unchanged: unchanged.map { |id| tracker_hash(id) })
        result[:no_trackers] = true if tracker_ids.empty?
        result
      end

      # The { id:, name: } hash of a tracker id.
      # @param tracker_id [Integer] The tracker ID.
      # @return [Hash] The tracker hash, or { id:, name: nil } when the tracker no longer exists.
      def tracker_hash(tracker_id)
        tracker = Tracker.find_by(id: tracker_id)
        tracker ? { id: tracker.id, name: tracker.name } : { id: tracker_id, name: nil }
      end

      # Check the permission to create a project (R-002): add_project for a
      # top-level project, add_subprojects on the given parent otherwise.
      # @param parent_id [Integer, nil] The requested parent project ID.
      # @return [void]
      # @raise [UserError] when the permission is missing or the parent is not
      #   visible or not accessible via AI Helper.
      def validate_create_permission!(parent_id)
        if parent_id.nil?
          unless User.current.allowed_to?(:add_project, nil, global: true)
            raise UserError, "Permission denied: add_project (top-level project)"
          end
          return
        end

        parent = Project.find_by(id: parent_id)
        if parent.nil? || !parent.visible? || !accessible_project?(parent)
          raise UserError, "Parent project not allowed: id = #{parent_id}"
        end
        unless User.current.allowed_to?(:add_subprojects, parent)
          raise UserError, "Permission denied: add_subprojects on project #{parent_id}"
        end
      end

      # Check the shape of the custom field entries, drop entries without a
      # field_id and symbolize keys.
      # @param custom_fields [Object] Raw custom field entries given by the caller.
      # @return [Array<Hash>] Entries having a field_id.
      # @raise [UserError] when the value is not an array of objects.
      def normalize_custom_fields(custom_fields)
        return [] if custom_fields.nil?
        raise UserError, "custom_fields must be an array" unless custom_fields.is_a?(Array)

        custom_fields.filter_map do |field|
          raise UserError, "custom_fields entries must be objects" unless field.is_a?(Hash)

          field = field.transform_keys(&:to_sym)
          if field[:field_id].nil?
            ai_helper_logger.warn("Skipping a project custom field entry without field_id")
            next
          end
          field
        end
      end

      # Reject custom fields that are not editable on the project by the current user.
      # @param project [Project] The project.
      # @param custom_fields [Array<Hash>] Entries already passed through {#normalize_custom_fields}.
      # @return [void]
      # @raise [UserError] if a field is not editable.
      def validate_custom_fields!(project, custom_fields)
        return if custom_fields.empty?

        editable_ids = project.editable_custom_field_values(User.current).map { |v| v.custom_field_id.to_s }
        invalid = custom_fields.map { |field| field[:field_id] }.reject { |id| editable_ids.include?(id.to_s) }
        return if invalid.empty?

        raise UserError, "Custom field not editable for projects: #{invalid.join(", ")}"
      end

      # Reject a publicity the current user may not set (Redmine would silently
      # drop the attribute). Only judged when the argument is given. For a new
      # project Redmine judges this against the role given to non-admin creators,
      # so the message carries a hint (R-003).
      # @param project [Project] The project (new or existing).
      # @param is_public [Boolean, nil] The requested publicity.
      # @return [void]
      # @raise [UserError] if the attribute is not safe for the current user.
      def validate_publicity!(project, is_public)
        return if is_public.nil?
        return if project.safe_attribute?("is_public", User.current)

        hint = project.new_record? ? " (the role given to non-admin creators lacks it)" : ""
        raise UserError, "Permission denied: select_project_publicity#{hint}"
      end

      # Reject a member-inheritance change the current user may not make.
      # Only judged when the argument is given.
      # @param project [Project] The project (new or existing).
      # @param inherit_members [Boolean, nil] The requested flag.
      # @return [void]
      # @raise [UserError] if the attribute is not safe for the current user.
      def validate_inherit_members!(project, inherit_members)
        return if inherit_members.nil?
        return if project.safe_attribute?("inherit_members", User.current)

        raise UserError, "Permission denied: manage_members (inherit_members)"
      end

      # Reject a parent the current user may not set. Redmine's safe_attributes=
      # would silently drop it and validate_parent would only say "invalid", so
      # the same conditions are checked here before assignment (FR-003a).
      # @param project [Project] The project.
      # @param parent_id [Integer, nil] The requested parent project ID.
      # @param clear_parent [Boolean, nil] true to make the project top-level.
      # @return [void]
      # @raise [UserError] if the parent is not found, not accessible, or not in
      #   the project's allowed_parents for the current user.
      def validate_parent!(project, parent_id, clear_parent)
        allowed = project.allowed_parents(User.current)
        if clear_parent == true
          unless allowed.include?(nil)
            raise UserError, "Parent project not allowed: top level is not allowed for project #{project.id}"
          end
          return
        end
        return if parent_id.nil?

        parent = Project.find_by(id: parent_id)
        if parent.nil? || !parent.visible? || !accessible_project?(parent) || allowed.exclude?(parent)
          raise UserError, "Parent project not allowed: id = #{parent_id}"
        end
      end

      # Build the attributes hash for Project#safe_attributes=, keeping only given values.
      # @param name [String, nil] The name.
      # @param description [String, nil] The description.
      # @param homepage [String, nil] The homepage.
      # @param is_public [Boolean, nil] The publicity.
      # @param parent_id [Integer, nil] The parent project ID.
      # @param clear_parent [Boolean, nil] true to make the project top-level.
      # @param inherit_members [Boolean, nil] The member inheritance flag.
      # @param custom_fields [Array<Hash>, nil] Entries already passed through {#normalize_custom_fields}.
      # @return [Hash] String-keyed attributes.
      def build_project_attributes(name: nil, description: nil, homepage: nil, is_public: nil,
                                   parent_id: nil, clear_parent: nil, inherit_members: nil, custom_fields: nil)
        attrs = {
          "name" => name, "description" => description, "homepage" => homepage,
          "is_public" => is_public, "inherit_members" => inherit_members
        }.compact
        if clear_parent == true
          attrs["parent_id"] = ""
        elsif !parent_id.nil?
          attrs["parent_id"] = parent_id.to_s
        end
        if custom_fields.present?
          attrs["custom_field_values"] = custom_fields.to_h { |field| [ field[:field_id].to_s, field[:value] ] }
        end
        attrs
      end

      # Convert a project to the Project hash of contracts/project_tools.md.
      # @param project [Project] The project.
      # @return [Hash] The project information.
      def project_to_hash(project)
        {
          id: project.id,
          name: project.name,
          identifier: project.identifier,
          description: project.description,
          homepage: project.homepage,
          is_public: project.is_public,
          parent: format_named_record(project.parent),
          inherit_members: project.inherit_members,
          status: project.status,
          custom_fields: project.visible_custom_field_values(User.current).map do |value|
            { id: value.custom_field.id, name: value.custom_field.name, value: value.value }
          end,
          enabled_modules: project.enabled_module_names,
          trackers: project.trackers.map { |tracker| format_named_record(tracker) },
          url_for_project: project_path(project, only_path: true)
        }
      end
    end
  end
end
