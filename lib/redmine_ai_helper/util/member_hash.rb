# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Shared serializer that renders a Redmine Member (membership) as the Member
    # hash defined in specs/084-project-management-tools/contracts/member_tools.md.
    # Used by ProjectTools#project_members and MemberTools#add_member /
    # #update_member_roles so that all of them return the same shape.
    module MemberHash
      # Convert a Member (membership) to the Member hash.
      # @param member [Member] The membership.
      # @return [Hash] The member information.
      def member_to_hash(member)
        principal = member.principal
        {
          member_id: member.id,
          user_id: member.user_id,
          login: principal.is_a?(Group) ? nil : principal.login,
          user_name: principal.name,
          type: principal_type(principal),
          status: principal_status(principal),
          roles: member.roles.map { |role| member_role_to_hash(member, role) },
          deletable: member.deletable?(User.current)
        }
      end

      # Convert one role of a membership to the role hash.
      # @param member [Member] The membership.
      # @param role [Role] The role.
      # @return [Hash] The role information.
      def member_role_to_hash(member, role)
        {
          id: role.id,
          name: role.name,
          inherited: member.has_inherited_role?(role),
          inherited_from: inherited_from_names(member, role),
          editable: member.role_editable?(role, User.current)
        }
      end

      # Names of the projects/groups a role was inherited from, joined with ", ".
      # @param member [Member] The membership.
      # @param role [Role] The role.
      # @return [String, nil] The inheritance source names, or nil when not inherited.
      def inherited_from_names(member, role)
        names = member.role_inheritance(role).map(&:name)
        names.empty? ? nil : names.join(", ")
      end

      # "user" or "group" for a principal.
      # @param principal [Principal] The user or group.
      # @return [String] The principal type.
      def principal_type(principal)
        principal.is_a?(Group) ? "group" : "user"
      end

      # "active", "registered", or "locked" for a principal.
      # @param principal [Principal] The user or group.
      # @return [String] The principal status.
      # @raise [RuntimeError] on an unknown status value from the database.
      def principal_status(principal)
        case principal.status
        when Principal::STATUS_ACTIVE then "active"
        when Principal::STATUS_REGISTERED then "registered"
        when Principal::STATUS_LOCKED then "locked"
        else raise "Unknown principal status: #{principal.status}"
        end
      end
    end
  end
end
