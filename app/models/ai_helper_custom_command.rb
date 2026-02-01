# Custom command model for AI Helper
#
# Stores custom commands that expand shortcuts into full prompts.
# Commands can be scoped to global, project, or user level with different priorities.
#
# @example Create a global command
#   AiHelperCustomCommand.create!(
#     name: 'summarize',
#     prompt: 'Please summarize: {input}',
#     command_type: :global,
#     user_id: current_user.id
#   )
#
# @example Find and expand a command
#   cmd = AiHelperCustomCommand.find_command(name: 'summarize', user: user, project: project)
#   expanded = cmd.expand(input: 'some text', user: user, project: project)
class AiHelperCustomCommand < ActiveRecord::Base
  # Enum definitions
  enum :command_type, { global: 0, project: 1, user: 2 }
  enum :user_scope, { common: 0, project_limited: 1 }

  # Associations
  belongs_to :project, optional: true
  belongs_to :user

  # Callbacks
  before_save :normalize_name

  # Validations
  validates :name, presence: true,
                   length: { maximum: 50 },
                   format: { with: /\A[a-zA-Z0-9_-]+\z/ }
  validates :prompt, presence: true
  validates :command_type, presence: true

  # Custom validations
  validate :validate_command_type_constraints
  validate :validate_unique_command_name

  # Scopes
  scope :global_commands, -> { where(command_type: :global) }
  scope :project_commands, ->(project_id) {
          where(command_type: :project, project_id: project_id)
        }
  scope :user_common_commands, ->(user_id) {
          where(command_type: :user, user_id: user_id, user_scope: :common)
        }
  scope :user_project_commands, ->(user_id, project_id) {
          where(command_type: :user, user_id: user_id, user_scope: :project_limited, project_id: project_id)
        }

  # Class methods
  def self.available_for(user:, project: nil)
    conditions = []
    params = []

    # Global commands
    conditions << "(command_type = ?)"
    params << command_types[:global]

    # Project commands (when project is specified)
    if project
      conditions << "(command_type = ? AND project_id = ?)"
      params << command_types[:project]
      params << project.id
    end

    # User's common commands
    conditions << "(command_type = ? AND user_id = ? AND user_scope = ?)"
    params << command_types[:user]
    params << user.id
    params << user_scopes[:common]

    # User's project-limited commands (when project is specified)
    if project
      conditions << "(command_type = ? AND user_id = ? AND user_scope = ? AND project_id = ?)"
      params << command_types[:user]
      params << user.id
      params << user_scopes[:project_limited]
      params << project.id
    end

    where(conditions.join(" OR "), *params)
  end

  # Find a command by name with priority-based resolution
  #
  # Commands are searched in priority order:
  # 1. User's project-limited commands (if project specified)
  # 2. User's common commands
  # 3. Project commands (if project specified)
  # 4. Global commands
  #
  # @param name [String] Command name (case-insensitive)
  # @param user [User] Current user
  # @param project [Project, nil] Current project (optional)
  # @return [AiHelperCustomCommand, nil] The found command or nil
  def self.find_command(name:, user:, project: nil)
    normalized_name = name.downcase

    # Priority 1: User's project-limited commands
    if project
      command = where(
        command_type: :user,
        user_id: user.id,
        user_scope: :project_limited,
        project_id: project.id,
        name: normalized_name,
      ).first
      return command if command
    end

    # Priority 2: User's common commands
    command = where(
      command_type: :user,
      user_id: user.id,
      user_scope: :common,
      name: normalized_name,
    ).first
    return command if command

    # Priority 3: Project commands
    if project
      command = where(
        command_type: :project,
        project_id: project.id,
        name: normalized_name,
      ).first
      return command if command
    end

    # Priority 4: Global commands
    where(
      command_type: :global,
      name: normalized_name,
    ).first
  end

  # Instance methods
  def expand(input: "", user:, project: nil, datetime: Time.current)
    result = prompt.dup

    # Expand variables
    result.gsub!("{input}", input.to_s)
    result.gsub!("{user_name}", user.name.to_s)
    result.gsub!("{project_name}", project ? project.name.to_s : "")
    result.gsub!("{datetime}", datetime.strftime("%Y-%m-%d %H:%M:%S"))

    result
  end

  def editable_by?(user)
    return false unless user
    user.admin? || self.user_id == user.id
  end

  def visible_to?(user, project: nil)
    return false unless user

    case command_type&.to_sym
    when :global
      true
    when :project
      # Project commands are visible to project members
      self.project && user.member_of?(self.project)
    when :user
      # User commands are visible only to the user who created them
      self.user_id == user.id
    else
      false
    end
  end

  private

  def normalize_name
    self.name = name.downcase if name.present?
  end

  def validate_command_type_constraints
    case command_type&.to_sym
    when :global
      # Global commands don't have project_id constraints
    when :project
      if project_id.blank?
        errors.add(:project, :required_for_project_command)
      end
    when :user
      if user_scope&.to_sym == :project_limited && project_id.blank?
        errors.add(:project, :required_for_project_limited)
      end
    end
  end

  def validate_unique_command_name
    return if name.blank?

    normalized_name = name.downcase

    scope = self.class.where.not(id: id)

    case command_type&.to_sym
    when :global
      if scope.where(command_type: :global, name: normalized_name).exists?
        errors.add(:name, :taken)
      end
    when :project
      if scope.where(command_type: :project, project_id: project_id, name: normalized_name).exists?
        errors.add(:name, :taken)
      end
    when :user
      if user_scope&.to_sym == :common
        if scope.where(command_type: :user, user_id: user_id, user_scope: :common, name: normalized_name).exists?
          errors.add(:name, :taken)
        end
      elsif user_scope&.to_sym == :project_limited
        if scope.where(command_type: :user, user_id: user_id, user_scope: :project_limited, project_id: project_id, name: normalized_name).exists?
          errors.add(:name, :taken)
        end
      end
    end
  end
end
