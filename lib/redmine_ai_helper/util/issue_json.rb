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
        json = {
          id: issue.id,
          subject: issue.subject,
          project: issue.project ? {
            id: issue.project.id,
            name: issue.project.name,
          } : nil,
          tracker: issue.tracker ? {
            id: issue.tracker.id,
            name: issue.tracker.name,
          } : nil,
          status: issue.status ? {
            id: issue.status.id,
            name: issue.status.name,
          } : nil,
          priority: issue.priority ? {
            id: issue.priority.id,
            name: issue.priority.name,
          } : nil,
          author: issue.author ? {
            id: issue.author.id,
            name: issue.author.name,
          } : nil,
          assigned_to: issue.assigned_to ? {
            id: issue.assigned_to.id,
            name: issue.assigned_to.name,
          } : nil,
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
          issue_url: issue.id ? issue_url(issue, only_path: true) : nil,
          attachments: issue.attachments.map do |attachment|
            {
              id: attachment.id,
              filename: attachment.filename,
              filesize: attachment.filesize,
              content_type: attachment.content_type,
              type: attachment_file_type(attachment),
              created_on: attachment.created_on,
              attachment_url: attachment_path(attachment, only_path: false),
            }
          end,
          children: issue.children.filter { |child| child.visible? }.map do |child|
            {
              id: child.id,
              tracker: child.tracker ? {
                id: child.tracker.id,
                name: child.tracker.name,
              } : nil,
              subject: child.subject,
              issue_url: issue_url(child, only_path: true),
            }
          end,
          relations: issue.relations.filter { |relation| relation.visible? }.map do |relation|
            {
              id: relation.id,
              issue_to_id: relation.issue_to_id,
              issue_from_id: relation.issue_from_id,
              relation_type: relation.relation_type,
              delay: relation.delay,
            }
          end,
          journals: issue.journals.filter { |journal| journal.visible? }.map do |journal|
            {
              id: journal.id,
              user: journal.user ? {
                id: journal.user.id,
                name: journal.user.name,
              } : nil,
              notes: journal.notes,
              created_on: journal.created_on,
              updated_on: journal.updated_on,
              private_notes: journal.private_notes,
              details: journal.details.map do |detail|
                {
                  id: detail.id,
                  property: detail.property,
                  prop_key: detail.prop_key,
                  value: detail.value,
                  old_value: detail.old_value,
                }
              end,
            }
          end,
          revisions: issue.changesets.map do |changeset|
            {
              repository_id: changeset.repository_id,
              revision: changeset.revision,
              committed_on: changeset.committed_on,
            }
          end,

        }
        json[:issue_url] = issue_url(issue, only_path: true) if issue.id

        json
      end
    end
  end
end
