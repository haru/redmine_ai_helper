# frozen_string_literal: true

# This file is part of Redmine AI Helper plugin for Redmine.
module RedmineAiHelper
  module Util
    # Utility module for converting Redmine issues to JSON format.
    # Provides methods to generate comprehensive JSON representations of issues
    # including related data like project, tracker, status, priority, assignees, attachments, etc.
    module IssueJson
      include RedmineAiHelper::Util::AttachmentFileHelper
      # Generates a JSON representation of an issue.
      # @param issue [Issue] The issue to be represented in JSON.
      # @return [Hash] A hash representing the issue in JSON format.
      def generate_issue_data(issue)
        build_issue_scalar_fields(issue).merge(
          attachments: issue.attachments.map { |a| format_issue_attachment(a) },
          children: issue.children.filter { |c| c.visible? }.map { |c| format_issue_child(c) },
          parent: format_issue_parent(issue),
          relations: issue.relations.filter { |r| r.visible? }.map { |r| format_issue_relation(issue, r) },
          journals: issue.journals.filter { |j| j.visible? }.map { |j| format_issue_journal(j) },
          revisions: issue.changesets.map { |c| { repository_id: c.repository_id, revision: c.revision, committed_on: c.committed_on } },
          custom_fields: format_issue_custom_fields(issue)
        )
      end

      # Summary-only role enrichment for the issue payload.
      #
      # This lives in a nested module instead of {IssueJson} itself so that the
      # "roles are attached on the issue summary path only" rule is structural:
      # classes that merely include {IssueJson} cannot produce the role-bearing
      # representation. Include it together with {IssueJson}, which it builds on.
      module WithRoles
        # Generates the issue payload used by the issue summary prompt.
        #
        # The result is identical to {#generate_issue_data} except that the author,
        # the assignee and every journal author carry a +roles+ array naming the roles
        # that principal holds in the issue's project.
        #
        # This representation is intended for the issue summary prompt only. Every other
        # consumer must keep using {#generate_issue_data}, which represents people as
        # bare +{id, name}+ records only.
        #
        # @param issue [Issue] The issue to be represented in JSON.
        # @return [Hash] The issue hash with project role names attached.
        def generate_issue_data_with_roles(issue)
          data = generate_issue_data(issue)
          role_names_by_id = project_role_names_by_principal_id(summary_principal_ids(data), issue.project)
          attach_roles(data[:author], role_names_by_id) if data[:author]
          attach_roles(data[:assigned_to], role_names_by_id) if data[:assigned_to]
          data[:journals].each { |journal| attach_roles(journal[:user], role_names_by_id) if journal[:user] }
          data
        end

        private

        # Collects the ids of the principals appearing in an issue payload.
        # @param data [Hash] The issue payload built by {#generate_issue_data}.
        # @return [Array<Integer>] The deduplicated principal ids (author, assignee, journal authors).
        def summary_principal_ids(data)
          ids = []
          ids << data[:author][:id] if data[:author]
          ids << data[:assigned_to][:id] if data[:assigned_to]
          data[:journals].each { |journal| ids << journal[:user][:id] if journal[:user] }
          ids.uniq
        end

        # Adds a +roles+ key with the principal's project role names to a node.
        # @param node [Hash] A named record hash ({id:, name:}).
        # @param role_names_by_id [Hash{Integer => Array<String>}] Role names indexed by principal id.
        def attach_roles(node, role_names_by_id)
          node[:roles] = role_names_by_id.fetch(node[:id], [])
        end

        # Maps principal ids to the role names they hold in the project via membership.
        # Works for both User and Group: Member#user_id holds a Principal id.
        # Principals without a membership are absent from the result. Built-in roles
        # (Non member / Anonymous) can never appear: Redmine validates membership
        # roles through MemberRole#validate_role_member, which requires
        # +role&.member?+ (Role#member? is +!builtin?+), and Redmine's built-in role
        # fallback for non-members is applied only in User#roles_for_project, a path
        # this method does not use.
        # @param principal_ids [Array<Integer>] The principal ids to resolve.
        # @param project [Project] The project in which the roles are held.
        # @return [Hash{Integer => Array<String>}] Role names per principal id, sorted ascending.
        def project_role_names_by_principal_id(principal_ids, project)
          return {} if principal_ids.empty?

          Member.where(project_id: project.id, user_id: principal_ids).includes(:roles)
            .each_with_object({}) do |member, hash|
              hash[member.user_id] = member.roles.map(&:name).uniq.sort
            end
        end
      end

      private

      def format_named_record(obj)
        return nil unless obj

        { id: obj.id, name: obj.name }
      end

      def build_issue_scalar_fields(issue)
        {
          id: issue.id,
          subject: issue.subject,
          project: format_named_record(issue.project),
          tracker: format_named_record(issue.tracker),
          status: format_named_record(issue.status),
          priority: format_named_record(issue.priority),
          author: format_named_record(issue.author),
          assigned_to: format_named_record(issue.assigned_to),
          description: issue.description,
          start_date: issue.start_date,
          due_date: issue.due_date,
          done_ratio: issue.done_ratio,
          is_private: issue.is_private,
          estimated_hours: issue.estimated_hours,
          total_estimated_hours: issue.total_estimated_hours,
          spent_hours: issue.spent_hours,
          total_spent_hours: issue.total_spent_hours,
          created_on: issue.created_on,
          updated_on: issue.updated_on,
          closed_on: issue.closed_on,
          issue_url: issue.id ? issue_url(issue, only_path: true) : nil
        }
      end


      def format_issue_parent(issue)
        return nil unless issue.parent && issue.parent.visible?

        { id: issue.parent.id, subject: issue.parent.subject }
      end

      def format_issue_attachment(attachment)
        {
          id: attachment.id,
          filename: attachment.filename,
          filesize: attachment.filesize,
          content_type: attachment.content_type,
          type: attachment_file_type(attachment),
          created_on: attachment.created_on,
          attachment_url: attachment_path(attachment, only_path: false)
        }
      end

      def format_issue_child(child)
        {
          id: child.id,
          tracker: child.tracker ? { id: child.tracker.id, name: child.tracker.name } : nil,
          subject: child.subject,
          issue_url: issue_url(child, only_path: true)
        }
      end

      def format_issue_relation(issue, relation)
        other_issue_id = relation.issue_from_id == issue.id ? relation.issue_to_id : relation.issue_from_id
        {
          id: relation.id,
          issue_to_id: relation.issue_to_id,
          issue_from_id: relation.issue_from_id,
          relation_type: relation.relation_type,
          delay: relation.delay,
          other_issue_id: other_issue_id,
          other_issue_subject: Issue.find_by(id: other_issue_id)&.subject
        }
      end

      def format_issue_custom_fields(issue)
        issue.custom_field_values.map do |cfv|
          { id: cfv.custom_field.id, name: cfv.custom_field.name, value: cfv.value }
        end
      end

      def format_issue_journal(journal)
        {
          id: journal.id,
          user: journal.user ? { id: journal.user.id, name: journal.user.name } : nil,
          notes: journal.notes,
          created_on: journal.created_on,
          updated_on: journal.updated_on,
          private_notes: journal.private_notes,
          details: journal.details.map { |d| { id: d.id, property: d.property, prop_key: d.prop_key, value: d.value, old_value: d.old_value } }
        }
      end
    end
  end
end
