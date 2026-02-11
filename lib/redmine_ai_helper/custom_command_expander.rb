module RedmineAiHelper
  # Expands custom commands in user messages
  #
  # Detects command patterns (starting with '/') in user input and expands them
  # into their full prompt templates with variable substitution.
  #
  # @example Basic usage
  #   expander = CustomCommandExpander.new(user: current_user, project: project)
  #   result = expander.expand('/summarize some text')
  #   # => { expanded: true, message: 'Please summarize: some text', command: <AiHelperCustomCommand> }
  class CustomCommandExpander
    # Regular expression pattern for matching commands
    # Matches: /command-name optional text following the command
    COMMAND_PATTERN = /\A\/([a-zA-Z0-9_-]+)(?:\s+(.*))?/m

    def initialize(user:, project: nil)
      @user = user
      @project = project
      @datetime = Time.current
    end

    # Check if the message is a command
    def command?(message)
      message.to_s.strip.start_with?('/')
    end

    # Expand the command
    # @param message [String] User input message
    # @return [Hash] { expanded: Boolean, message: String, command: AiHelperCustomCommand }
    def expand(message)
      return { expanded: false, message: message } unless command?(message)

      match = message.match(COMMAND_PATTERN)
      return { expanded: false, message: message } unless match

      command_name = match[1].downcase
      input_text = match[2] || ''

      custom_command = AiHelperCustomCommand.find_command(
        name: command_name,
        user: @user,
        project: @project
      )

      return { expanded: false, message: message } unless custom_command

      expanded_message = custom_command.expand(
        input: input_text.strip,
        user: @user,
        project: @project,
        datetime: @datetime
      )

      { expanded: true, message: expanded_message, command: custom_command }
    end

    # Get list of available commands (for completion)
    # @param prefix [String] Command name prefix
    # @return [Array<Hash>] Array of command information
    def available_commands(prefix: nil)
      commands = AiHelperCustomCommand.available_for(
        user: @user,
        project: @project
      )

      if prefix.present?
        commands = commands.where('LOWER(name) LIKE ?', "#{prefix.downcase}%")
      end

      commands.order(:name).map do |cmd|
        {
          name: cmd.name,
          description: cmd.description
        }
      end
    end
  end
end
