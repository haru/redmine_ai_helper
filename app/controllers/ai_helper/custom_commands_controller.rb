module AiHelper
  # Controller for managing custom commands
  #
  # Provides CRUD operations for custom commands that can be used
  # to expand shortcuts into full prompts in the AI Helper chat interface.
  class CustomCommandsController < ApplicationController
    menu_item :ai_helper_dashboard

    before_action :require_login
    before_action :find_project, only: [:index, :new, :create, :edit, :update, :destroy, :available]
    before_action :authorize_ai_helper, only: [:index, :available]
    before_action :find_command, only: [:edit, :update, :destroy]
    before_action :authorize_command_edit, only: [:edit, :update, :destroy]

    # GET /projects/:project_id/ai_helper/custom_commands
    # GET /ai_helper/custom_commands
    def index
      @commands = AiHelperCustomCommand.available_for(
        user: User.current,
        project: @project,
      ).order(:command_type, :name)

      @grouped_commands = @commands.group_by(&:command_type)
    end

    # GET /projects/:project_id/ai_helper/custom_commands/available
    # GET /ai_helper/custom_commands/available
    def available
      expander = RedmineAiHelper::CustomCommandExpander.new(
        user: User.current,
        project: @project,
      )

      prefix = params[:prefix]
      commands = expander.available_commands(prefix: prefix)

      render json: { commands: commands }
    end

    # GET /projects/:project_id/ai_helper/custom_commands/new
    # GET /ai_helper/custom_commands/new
    def new
      @command = AiHelperCustomCommand.new(
        user: User.current,
        project: @project,
      )
    end

    # POST /projects/:project_id/ai_helper/custom_commands
    # POST /ai_helper/custom_commands
    def create
      @command = AiHelperCustomCommand.new(command_params)
      @command.user = User.current
      # Force project based on current context; user cannot set project via form
      @command.project = @project

      if @command.save
        flash[:notice] = l(:notice_successful_create)
        redirect_to_command_list
      else
        render :new
      end
    end

    # GET /projects/:project_id/ai_helper/custom_commands/:id/edit
    # GET /ai_helper/custom_commands/:id/edit
    def edit
    end

    # PATCH/PUT /projects/:project_id/ai_helper/custom_commands/:id
    # PATCH/PUT /ai_helper/custom_commands/:id
    def update
      # Apply permitted params then force project based on context
      @command.assign_attributes(command_params)
      @command.project = @project
      if @command.save
        flash[:notice] = l(:notice_successful_update)
        redirect_to_command_list
      else
        render :edit
      end
    end

    # DELETE /projects/:project_id/ai_helper/custom_commands/:id
    # DELETE /ai_helper/custom_commands/:id
    def destroy
      @command.destroy
      flash[:notice] = l(:notice_successful_delete)
      redirect_to_command_list
    end

    private

    def find_project
      @project = Project.find(params[:project_id]) if params[:project_id]
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def find_command
      @command = AiHelperCustomCommand.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def authorize_ai_helper
      # Check AI helper usage permission
      if @project
        # Project context: requires view_ai_helper permission
        return if User.current.allowed_to?(:view_ai_helper, @project)
      else
        # Global context: allowed if logged in
        return if User.current.logged?
      end
      render_403
    end

    def authorize_command_edit
      return if @command.editable_by?(User.current)
      render_403
    end

    def command_params
      params.require(:ai_helper_custom_command).permit(
        :name, :prompt, :command_type, :user_scope
      )
    end

    def redirect_to_command_list
      if @project
        redirect_to ai_helper_dashboard_path(@project, tab: "custom_commands")
      else
        redirect_to custom_commands_path
      end
    end
  end
end
