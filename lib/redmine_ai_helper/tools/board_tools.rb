# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/attachment_file_helper"

module RedmineAiHelper
  module Tools
    # Tools for handling Redmine board-related queries.
    class BoardTools < RedmineAiHelper::BaseTools
      define_function :list_boards, description: "List all boards in the project. It returns the board ID, project ID, name, description, messages_count, and last_message." do
        property :project_id, type: "integer", description: "The project ID of the project to return.", required: true
      end

      # List all boards in the project.
      # @param project_id [Integer] The project ID of the project to return.
      # @return [Array<Hash>] An array of hashes containing board information.
      def list_boards(project_id:)
        project = Project.find_by(id: project_id)
        raise("Project not found") if project.nil?
        boards = project.boards.filter { |b| b.visible? }
        board_list = []
        boards.each do |board|
          board_list << {
            id: board.id,
            name: board.name,
            description: board.description,
            messages_count: board.messages_count,
            parent_board_id: board.parent_id,
            url_for_board: "#{project_board_path(board.project, board)}",
          }
        end
        return board_list
      end

      define_function :board_info, description: "Read a board from the database. It returns the board ID, project ID, name, description, messages_count, and messages." do
        property :board_id, type: "integer", description: "The board ID of the board to return.", required: true
      end

      # Read a board from the database.
      # @param board_id [Integer] The board ID of the board to return.
      # @return [Hash] A hash containing board information.
      def board_info(board_id:)
        board = Board.find_by(id: board_id)
        raise("Board not found") if board.nil?
        board_hash = {
          id: board.id,
          project_id: board.project_id,
          name: board.name,
          description: board.description,
          url_for_board: "#{project_board_path(board.project, board)}",
          messages: board.messages.filter { |m| m.visible? }.map do |message|
            hash = {
              id: message.id,
              content: message.content,
              created_on: message.created_on,
              url_for_message: "#{board_message_path(message.board, message)}",
            }
            hash[:author] = {
              id: message.author.id,
              name: message.author.name,
            } if message.author
            hash
          end,
        }
        board_hash
      end

      define_function :read_message, description: "Read a message from the database. It returns the message ID, board ID, parent_id, subject, content, author, created_on, updated_on, and replies." do
        property :message_id, type: "integer", description: "The message ID of the message to return.", required: true
      end
      # Read a message from the database and return it as a JSON object.
      # @param message_id [Integer] The message ID of the message to return.
      # @return [Hash] A hash containing message information.
      def read_message(message_id:)
        message = Message.find_by(id: message_id)
        raise("Message not found") if message.nil? || !message.visible?
        message_hash = {
          id: message.id,
          board_id: message.board_id,
          parent_id: message.parent_id,
          subject: message.subject,
          content: message.content,
          author: {
            id: message.author.id,
            name: message.author.name,
          },
          created_on: message.created_on,
          updated_on: message.updated_on,
          url_for_message: "#{board_message_path(message.board, message)}",
          attachments: message.attachments.map do |attachment|
            {
              id: attachment.id,
              filename: attachment.filename,
              filesize: attachment.filesize,
              content_type: attachment.content_type,
              type: attachment.image? ? "image" : nil,
              created_on: attachment.created_on,
            }
          end,
          replies: message.children.filter(&:visible?).map do |reply|
            {
              id: reply.id,
              content: reply.content,
              author: {
                id: reply.author.id,
                name: reply.author.name,
              },
              created_on: reply.created_on,
              updated_on: reply.updated_on,
            }
          end,
        }

        message_hash
      end

      define_function :generate_url_for_board, description: "Generate a URL for the specified board. It returns the board's URL." do
        property :board_id, type: "integer", description: "The board ID of the board to return.", required: true
      end
      # Generate a URL for the specified board.
      # @param board_id [Integer] The board ID of the board to return.
      # @return url.
      def generate_board_url(board_id:)
        raise("Board ID not provided") unless board_id
        board = Board.find_by(id: board_id)
        raise("Board not found") if board.nil? || !board.visible?
        url = "#{project_board_path(board.project, board)}"

        { url: url }
      end

      define_function :generate_url_for_message, description: "Generate a URL for the specified message. It returns the message's URL." do
        property :message_id, type: "integer", description: "The message ID of the message to return.", required: true
      end

      # Generate a URL for the specified message.
      # @param message_id [Integer] The message ID of the message to return.
      # @return url.
      def generate_message_url(message_id:)
        raise("Message ID not provided") unless message_id
        message = Message.find_by(id: message_id)
        raise("Message not found") if message.nil? || !message.visible?
        url = "#{board_message_path(message.board, message)}"

        { url: url }
      end
    end
  end
end
