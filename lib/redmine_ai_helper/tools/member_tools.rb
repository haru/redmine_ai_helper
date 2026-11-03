# frozen_string_literal: true

require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/project_write_guard"
require "redmine_ai_helper/util/member_hash"

module RedmineAiHelper
  module Tools
    # MemberTools provides member management operations for a project:
    # finding candidates to add, listing the roles the caller can manage,
    # adding members, changing their roles, and removing them.
    class MemberTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::ProjectWriteGuard
      include RedmineAiHelper::Util::MemberHash

      define_function :find_member_candidates, description: "Find users or groups that can be added to a project: active, visible to you, and not yet members of the project. Search matches login, name, or email. Returns at most 100 candidates with truncated set to true when more exist." do
        property :project_id, type: "integer", description: "The ID of the project to add members to.", required: true
        property :query, type: "string", description: "The name, login, or email fragment to search for.", required: true
      end
      # Find principals that can be added to the project.
      # @param project_id [Integer] The project ID.
      # @param query [String] The name, login, or email fragment to search for.
      # @return [Hash] { candidates: [ { id:, name:, login:, type: } ], truncated: Boolean },
      #   or { error: } for a user-caused failure.
      def find_member_candidates(project_id:, query:)
        user_errors_as_result do
          project = readable_project!(project_id: project_id, permission: :manage_members)
          raise UserError, "query is required" if query.nil?

          found = Principal.active.visible.not_member_of(project).like(query).limit(101).to_a
          truncated = found.size > 100
          {
            candidates: found.first(100).map { |principal| principal_to_hash(principal) },
            truncated: truncated
          }
        end
      end

      define_function :list_managed_roles, description: "List the roles you can grant or revoke in a project. Only these roles can be used in add_member and update_member_roles." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
      end
      # List the roles the current user can manage in the project.
      # @param project_id [Integer] The project ID.
      # @return [Hash] { roles: [ { id:, name: } ] }, or { error: } for a user-caused failure.
      def list_managed_roles(project_id:)
        user_errors_as_result do
          project = readable_project!(project_id: project_id, permission: :manage_members)

          { roles: User.current.managed_roles(project).map { |role| { id: role.id, name: role.name } } }
        end
      end

      define_function :add_member, write: true, description: "Add a user or group to a project with one or more roles. The roles must be in list_managed_roles. If the principal is already a member, nothing is added and the current roles are reported in the error." do
        property :project_id, type: "integer", description: "The ID of the project to add the member to.", required: true
        property :principal_id, type: "integer", description: "The ID of the user or group to add. Use find_member_candidates to look it up.", required: true
        property :role_ids, type: "array", description: "The IDs of the roles to grant. At least one role is required. Use list_managed_roles to look them up.", required: true do
          item type: "integer"
        end
      end
      # Add a principal to the project with the given roles.
      # @param project_id [Integer] The project ID.
      # @param principal_id [Integer] The user or group ID.
      # @param role_ids [Array<Integer>] The role IDs to grant (at least one).
      # @return [Hash] The Member hash with project:, or { error: } for a user-caused failure.
      def add_member(project_id:, principal_id:, role_ids:)
        user_errors_as_result do
          project = writable_project!(project_id: project_id, permission: :manage_members)
          raise UserError, "principal_id is required" if principal_id.nil?
          role_ids = validate_role_ids!(project, role_ids)

          principal = Principal.active.visible.find_by(id: principal_id)
          if principal.nil?
            raise UserError, "Principal cannot be added: id = #{principal_id} (locked, not visible, or not found)"
          end
          existing = project.memberships.find_by(user_id: principal_id)
          if existing
            raise UserError, "Already a member: id = #{principal_id}, roles: #{existing.roles.map(&:name).join(", ")}"
          end

          member = Member.new(project: project, principal: principal)
          member.role_ids = role_ids
          raise UserError, "Failed to add member: #{member.errors.full_messages.join(", ")}" unless member.save

          member_to_hash(member).merge(project: format_named_record(project))
        end
      end

      define_function :update_member_roles, write: true, description: "Change the roles directly granted to an existing member: add roles, remove roles, or give both lists to replace them. Roles inherited from a parent project or a group cannot be changed here. A member cannot be left without any role; use remove_member to remove the member entirely." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
        property :principal_id, type: "integer", description: "The ID of the user or group. Use project_members to look it up.", required: true
        property :add_role_ids, type: "array", description: "The IDs of the roles to grant. Use list_managed_roles to look them up.", required: false do
          item type: "integer"
        end
        property :remove_role_ids, type: "array", description: "The IDs of the directly granted roles to revoke. Inherited roles are rejected.", required: false do
          item type: "integer"
        end
      end
      # Update the directly granted roles of an existing member.
      # @param project_id [Integer] The project ID.
      # @param principal_id [Integer] The user or group ID.
      # @param add_role_ids [Array<Integer>, nil] The role IDs to grant.
      # @param remove_role_ids [Array<Integer>, nil] The directly granted role IDs to revoke.
      # @return [Hash] The Member hash with project: and unchanged_role_ids:,
      #   or { error: } for a user-caused failure.
      def update_member_roles(project_id:, principal_id:, add_role_ids: nil, remove_role_ids: nil)
        user_errors_as_result do
          project = writable_project!(project_id: project_id, permission: :manage_members)
          raise UserError, "principal_id is required" if principal_id.nil?

          add_role_ids = validate_id_list!(add_role_ids, "add_role_ids")
          remove_role_ids = validate_id_list!(remove_role_ids, "remove_role_ids")
          if add_role_ids.empty? && remove_role_ids.empty?
            raise UserError, "add_role_ids or remove_role_ids is required"
          end
          overlap = add_role_ids & remove_role_ids
          if overlap.any?
            raise UserError, "The same role cannot be added and removed: #{overlap.join(", ")}"
          end
          validate_role_ids!(project, (add_role_ids + remove_role_ids).uniq)

          member = project.memberships.find_by(user_id: principal_id)
          raise UserError, "Not a member: principal id = #{principal_id}" if member.nil?

          inherited, direct = member.member_roles.partition { |mr| mr.inherited_from.present? }
          direct_role_ids = direct.map(&:role_id)
          inherited_role_ids = inherited.map(&:role_id)
          inherited_removed = remove_role_ids & inherited_role_ids
          unless inherited_removed.empty?
            raise UserError, "Inherited roles cannot be changed: #{role_labels(inherited_removed).join(", ")}"
          end

          unchanged = ((add_role_ids & member.role_ids) + (remove_role_ids - member.role_ids)).uniq
          new_role_ids = (direct_role_ids | add_role_ids) - remove_role_ids
          # Member#role_ids= keeps the inherited roles, so they count for the
          # "must keep at least one role" judgment.
          if (new_role_ids | inherited_role_ids).empty?
            raise UserError, "A member must keep at least one role; use remove_member to remove the member"
          end

          # role_ids= writes immediately, so assignment and save share a transaction:
          # a failed save must not leave the change behind.
          ActiveRecord::Base.transaction do
            member.role_ids = new_role_ids
            raise UserError, "Failed to update member roles: #{member.errors.full_messages.join(", ")}" unless member.save
          end

          member_to_hash(member).merge(project: format_named_record(project), unchanged_role_ids: unchanged.sort)
        end
      end

      define_function :remove_member, write: true, description: "Remove a member (a user or a group) from a project. The user, group, or issues are not deleted, but the member stops being the assignee of issue categories and of the project's default assignee. Always confirm with the user before removing: show the target member and their current roles first. Members with inherited roles, or with roles you cannot manage, cannot be removed." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
        property :principal_id, type: "integer", description: "The ID of the user or group to remove. Use project_members to look it up.", required: true
      end
      # Remove a member from the project. The member must have no inherited role
      # and only roles manageable by the current user (Member#deletable?).
      # @param project_id [Integer] The project ID.
      # @param principal_id [Integer] The user or group ID.
      # @return [Hash] { removed: true, project_id:, principal:, roles: },
      #   or { error: } for a user-caused failure.
      def remove_member(project_id:, principal_id:)
        user_errors_as_result do
          project = writable_project!(project_id: project_id, permission: :manage_members)
          raise UserError, "principal_id is required" if principal_id.nil?

          member = project.memberships.find_by(user_id: principal_id)
          raise UserError, "Not a member: principal id = #{principal_id}" if member.nil?

          if member.any_inherited_role?
            sources = member.member_roles.select { |mr| mr.inherited_from.present? }
              .flat_map { |mr| member.role_inheritance(mr.role) }.map(&:name).uniq
            raise UserError, "Member has roles inherited from #{sources.join(", ")}"
          end
          unless member.deletable?(User.current)
            unmanageable = (member.roles - User.current.managed_roles(project)).map(&:name)
            raise UserError, "Member has roles you cannot manage: #{unmanageable.join(", ")}"
          end

          principal = principal_to_hash(member.principal)
          roles = member.roles.map(&:name)
          # Member#destroy removes the member roles first; destroy! in a transaction
          # raises (and rolls those back) when the member itself cannot be destroyed.
          ActiveRecord::Base.transaction { member.destroy! }

          { removed: true, project_id: project.id, principal: principal, roles: roles }
        end
      end

      private

      # Validate the role id list: an array of integers naming existing roles that
      # the current user can manage in the project. One invalid role rejects the
      # whole list.
      # @param project [Project] The project.
      # @param role_ids [Object] The role IDs given by the caller.
      # @return [Array<Integer>] The validated role IDs without duplicates.
      # @raise [UserError] when the value is not an array of integers, the list is
      #   empty, a role does not exist, or a role is not manageable by the current user.
      def validate_role_ids!(project, role_ids)
        raise UserError, "role_ids must be an array of integers" unless role_ids.is_a?(Array) && role_ids.all?(Integer)
        raise UserError, "role_ids is required (at least one role)" if role_ids.empty?

        role_ids = role_ids.uniq
        missing = role_ids - Role.where(id: role_ids).pluck(:id)
        raise UserError, "Role not found: #{missing.join(", ")}" if missing.any?

        unmanageable = role_ids - User.current.managed_roles(project).map(&:id)
        raise UserError, "Roles you cannot manage: #{role_labels(unmanageable).join(", ")}" if unmanageable.any?

        role_ids
      end

      # Validate an optional list of integer ids.
      # @param value [Object] The value given by the caller.
      # @param name [String] The argument name for the error message.
      # @return [Array<Integer>] The list (empty when nil).
      # @raise [UserError] when the value is neither nil nor an array of integers.
      def validate_id_list!(value, name)
        return [] if value.nil?
        raise UserError, "#{name} must be an array of integers" unless value.is_a?(Array) && value.all?(Integer)

        value.uniq
      end

      # "id (name)" labels for role ids, loading the names in one query.
      # @param ids [Array<Integer>] The role IDs.
      # @return [Array<String>] The labels.
      def role_labels(ids)
        names = Role.where(id: ids).index_by(&:id)
        ids.map { |id| "#{id} (#{names[id]&.name})" }
      end

      # Convert a candidate principal to the candidate hash of contracts/member_tools.md.
      # @param principal [Principal] The user or group.
      # @return [Hash] { id:, name:, login:, type: }.
      def principal_to_hash(principal)
        {
          id: principal.id,
          name: principal.name,
          login: principal.is_a?(Group) ? nil : principal.login,
          type: principal_type(principal)
        }
      end
    end
  end
end
