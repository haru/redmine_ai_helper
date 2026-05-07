# frozen_string_literal: true

require "redmine_ai_helper/base_tools"

module RedmineAiHelper
  module Tools
    # RepositoryTools is a specialized tool provider for handling Redmine repository-related queries.
    class RepositoryTools < RedmineAiHelper::BaseTools
      define_function :repository_info, description: "Get information about a repository." do
        property :repository_id, type: "integer", description: "The ID of the repository to get information about.", required: true
      end
      # Get information about a repository.
      # @param repository_id [Integer] The ID of the repository to get information about.
      # @return [Hash] A hash containing repository information.
      def repository_info(repository_id:)
        repository = Repository.find_by(id: repository_id)
        raise("Repository not found.") if repository.nil?
        json = {
          id: repository.id,
          type: repository.scm_name,
          name: repository.name,
          tags: repository.tags,
          branches: repository.branches,
          default_branch: repository.default_branch,
          url: url_for(controller: "repositories", action: "show", id: repository.project, repository_id: repository, only_path: true)
        }

        json
      end

      define_function :get_revision_info, description: "Get information about a revision in a repository. Returns the author, committed_on, list of path, and comments for the revision." do
        property :repository_id, type: "integer", description: "The ID of the repository to get information about.", required: true
        property :revision, type: "string", description: "The revision to get information about.", required: true
      end
      # Get information about a revision in a repository.
      # Returns the author, committed_on, list of path, and comments for the revision.
      # @param repository_id [Integer] The ID of the repository to get information about.
      # @param revision [String] The revision to get information about.
      # @return [Hash] A hash containing revision information.
      def get_revision_info(repository_id:, revision:)
        repository = Repository.find_by(id: repository_id)
        raise("Repository not found: repository_id = #{repository_id}") if repository.nil?
        changeset = repository.find_changeset_by_name(revision)
        raise("Revision not found: revision = #{revision}") if changeset.nil?
        user = changeset.user
        author_info = {
          id: user.id,
          name: user.name
        } if user
        author_info = changeset.author if author_info.nil?
        revision_info = {
          repository_id: repository_id,
          author: author_info,
          committed_on: changeset.committed_on,
          paths: changeset.filechanges.map { |f| f.path },
          comments: changeset.comments,
          revision: changeset.revision,
          related_issues: changeset.issues.filter { |i| i.visible? }.map { |i| { id: i.id, subject: i.subject } }
        }
        revision_info
      end

      define_function :get_file_info, description: "Get information about a file in a repository." do
        property :repository_id, type: "integer", description: "The ID of the repository to get information about.", required: true
        property :path, type: "string", description: "The path of the file to get information about.", required: true
        property :revision, type: "string", description: "The revision to get information about.", required: false
      end
      # Get information about a file in a repository.
      # @param repository_id [Integer] The ID of the repository to get information about.
      # @param path [String] The path of the file to get information about.
      # @param revision [String] The revision to get information about.
      # @return [Hash] A hash containing file information.
      def get_file_info(repository_id:, path:, revision: "main")
        repository = Repository.find_by(id: repository_id)
        raise("Repository not found.") if repository.nil?
        entry = repository.entry(path, revision)
        raise("File not found: path = #{path}, revision = #{revision}") if entry.nil?
        changeset = repository.find_changeset_by_name(revision)
        author_info = nil
        if changeset
          user = changeset.user
          author_info = {
            id: user.id,
            name: user.name
          } if user
          author_info = changeset.committer if author_info.nil?
        end
        commit_info = {
          author: author_info,
          committed_on: changeset.committed_on,
          comments: changeset.comments,
          revision: changeset.revision

        } unless changeset.nil?
        json = {
          size: entry.size,
          type: entry.is_file? ? "file" : "directory",
          is_text: entry.is_text?,
          url_for_this_redmine: url_for(controller: "repositories", action: "entry", id: repository.project, repository_id: repository, path: path, rev: revision, only_path: true),
          commit: commit_info
        }
        json
      end

      define_function :read_file, description: "Read a file in a repository." do
        property :repository_id, type: "integer", description: "The ID of the repository to read the file from.", required: true
        property :path, type: "string", description: "The path of the file to read.", required: true
        property :revision, type: "string", description: "The revision to read the file from.", required: false
      end
      # Read a file in a repository.
      # @param repository_id [Integer] The ID of the repository to read the file from.
      # @param path [String] The path of the file to read.
      # @param revision [String] The revision to read the file from.
      # @return [Hash] A hash containing the file content and URL for the file in Redmine.
      def read_file(repository_id:, path:, revision: "main")
        repository = Repository.find_by(id: repository_id)
        raise("Repository not found.") if repository.nil?

        entry = repository.entry(path, revision)
        raise("File not found: path = #{path}, revision = #{revision}") if entry.nil?

        raise("File is not text: path = #{path}, revision = #{revision}") unless entry.is_text?

        raise("#{path} is a directory.") if entry.is_dir?

        content = repository.cat(path, revision)
        json = {
          content: content,
          url_for_this_redmine: url_for(controller: "repositories", action: "entry", id: repository.project, repository_id: repository, path: path, rev: revision, only_path: true)
        }
        json
      end

      define_function :read_diff, description: "Get the diff information for a specified path and revision within the repository. If the path is not specified, the diff information for all files in the revision is returned." do
        property :repository_id, type: "integer", description: "The ID of the repository to get diff information from.", required: true
        property :path, type: "string", description: "The path of the file to get diff information about.", required: false
        property :revision, type: "string", description: "The revision to get diff information about.", required: true
        property :revision_to, type: "string", description: "The revision to compare the diff against.", required: false
      end
      # Get the diff information for a specified path and revision within the repository.
      # If the path is not specified, the diff information for all files in the revision is returned.
      # @param repository_id [Integer] The ID of the repository to get diff information from.
      # @param path [String] The path of the file to get diff information about.
      # @param revision [String] The revision to get diff information about.
      # @param revision_to [String] The revision to compare the diff against.
      # @return [Hash] A hash containing the diff information.
      def read_diff(repository_id:, path: nil, revision:, revision_to: nil)
        repository = Repository.find(repository_id)
        raise("Repository not found.") if repository.nil?

        changeset = repository.find_changeset_by_name(revision)
        raise("Revision not found: revision = #{revision}") if changeset.nil?

        rev_from = revision
        rev_to = revision_to
        if revision_to
          changeset_to = repository.find_changeset_by_name(revision_to)
          if changeset_to.committed_on > changeset.committed_on
            rev_from = revision_to
            rev_to = revision
          end
        end

        diff_lines = repository.diff(path, rev_from, rev_to)

        diff_text = diff_lines.join("\n")
        diff_text.force_encoding("UTF-8")

        json = {
          repository_id: repository_id,
          revision: revision,
          diff: diff_text
        }

        json
      end
    end
  end
end
