require File.expand_path("../../../test_helper", __FILE__)

module AiHelper
  class CustomCommandsControllerTest < ActionController::TestCase
    fixtures :users, :projects, :roles, :members, :member_roles

    def setup
      @controller = AiHelper::CustomCommandsController.new
      @request = ActionController::TestRequest.create(@controller.class)
      @response = ActionDispatch::TestResponse.new

      @user = User.find(2)
      @request.session[:user_id] = @user.id
      @project = Project.find(1)

      # Grant view_ai_helper permission to the user's role
      Role.find(1).add_permission!(:view_ai_helper)

      # Create test commands
      @global_command = AiHelperCustomCommand.create!(
        name: "global-test",
        prompt: "Global test prompt",
        command_type: :global,
        user_id: @user.id,
      )

      @project_command = AiHelperCustomCommand.create!(
        name: "project-test",
        prompt: "Project test prompt",
        command_type: :project,
        project_id: @project.id,
        user_id: @user.id,
      )

      @user_command = AiHelperCustomCommand.create!(
        name: "user-test",
        prompt: "User test prompt",
        command_type: :user,
        user_scope: :common,
        user_id: @user.id,
      )
    end

    context "GET index" do
      should "redirect to dashboard for project context" do
        @user.stubs(:allowed_to?).returns(true)
        User.stubs(:current).returns(@user)
        # Use project_id param since no project-scoped index route exists;
        # find_project still handles params[:project_id] for backward compatibility
        get :index, params: { project_id: @project.id }
        assert_redirected_to ai_helper_dashboard_path(@project, tab: "custom_commands")
      end

      should "show commands without project" do
        get :index
        assert_response :success
        assert_not_nil assigns(:commands)
        assert_not_nil assigns(:grouped_commands)
      end

      should "require login" do
        @request.session[:user_id] = nil
        get :index, params: { id: @project.id }
        assert_response 302
      end
    end

    context "GET available" do
      should "return commands as JSON" do
        @user.stubs(:allowed_to?).returns(true)
        User.stubs(:current).returns(@user)
        get :available, params: { id: @project.id, format: :json }
        assert_response :success
        json = JSON.parse(response.body)
        assert_not_nil json["commands"]
        assert_kind_of Array, json["commands"]
      end

      should "filter by prefix" do
        @user.stubs(:allowed_to?).returns(true)
        User.stubs(:current).returns(@user)
        get :available, params: {
                      id: @project.id,
                      prefix: "global",
                      format: :json,
                    }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 1, json["commands"].select { |c| c["name"].start_with?("global") }.count
      end

      should "work without project" do
        @user.stubs(:logged?).returns(true)
        @user.stubs(:allowed_to?).returns(true)
        User.stubs(:current).returns(@user)
        get :available, params: { format: :json }
        assert_response :success
        json = JSON.parse(response.body)
        assert_not_nil json["commands"]
      end

      should "include description in available commands JSON" do
        @global_command.update!(description: "Test description")
        @user.stubs(:allowed_to?).returns(true)
        User.stubs(:current).returns(@user)
        get :available, params: { id: @project.id, format: :json }
        assert_response :success
        json = JSON.parse(response.body)
        command = json["commands"].find { |c| c["name"] == "global-test" }
        assert_not_nil command
        assert_equal "Test description", command["description"]
      end
    end

    context "GET new" do
      should "render new form for project" do
        get :new, params: { id: @project.id }
        assert_response :success
        assert_not_nil assigns(:command)
        assert_equal @project, assigns(:command).project
      end

      should "render new form without project" do
        get :new
        assert_response :success
        assert_not_nil assigns(:command)
        assert_nil assigns(:command).project
      end
    end

    context "POST create" do
      should "create global command" do
        assert_difference "AiHelperCustomCommand.count", 1 do
          post :create, params: {
                     ai_helper_custom_command: {
                       name: "new-global",
                       prompt: "New global prompt",
                       command_type: "global",
                     },
                   }
        end
        assert_redirected_to custom_commands_path

        command = AiHelperCustomCommand.last
        assert_equal "new-global", command.name
        assert_equal "global", command.command_type
        assert_equal @user.id, command.user_id
      end

      should "create project command" do
        assert_difference "AiHelperCustomCommand.count", 1 do
          post :create, params: {
                     id: @project.id,
                     ai_helper_custom_command: {
                       name: "new-project",
                       prompt: "New project prompt",
                       command_type: "project",
                     },
                   }
        end
        assert_redirected_to ai_helper_dashboard_path(@project, tab: "custom_commands")

        command = AiHelperCustomCommand.last
        assert_equal "new-project", command.name
        assert_equal "project", command.command_type
        assert_equal @project.id, command.project_id
      end

      should "create user command" do
        assert_difference "AiHelperCustomCommand.count", 1 do
          post :create, params: {
                     ai_helper_custom_command: {
                       name: "new-user",
                       prompt: "New user prompt",
                       command_type: "user",
                       user_scope: "common",
                     },
                   }
        end
        assert_redirected_to custom_commands_path

        command = AiHelperCustomCommand.last
        assert_equal "new-user", command.name
        assert_equal "user", command.command_type
        assert_equal "common", command.user_scope
      end

      should "validate command name uniqueness" do
        assert_no_difference "AiHelperCustomCommand.count" do
          post :create, params: {
                     ai_helper_custom_command: {
                       name: "global-test",
                       prompt: "Duplicate prompt",
                       command_type: "global",
                     },
                   }
        end
        assert_response :success
        assert_not_nil assigns(:command).errors[:name]
      end

      should "validate required fields" do
        assert_no_difference "AiHelperCustomCommand.count" do
          post :create, params: {
                     ai_helper_custom_command: {
                       name: "",
                       prompt: "",
                       command_type: "global",
                     },
                   }
        end
        assert_response :success
        assert_not_nil assigns(:command).errors[:name]
        assert_not_nil assigns(:command).errors[:prompt]
      end

      should "create command with description" do
        assert_difference "AiHelperCustomCommand.count", 1 do
          post :create, params: {
            ai_helper_custom_command: {
              name: "with-desc",
              prompt: "Test prompt",
              description: "A helpful command",
              command_type: "global",
            },
          }
        end
        assert_redirected_to custom_commands_path

        command = AiHelperCustomCommand.last
        assert_equal "with-desc", command.name
        assert_equal "A helpful command", command.description
      end

      should "create command without description" do
        assert_difference "AiHelperCustomCommand.count", 1 do
          post :create, params: {
            ai_helper_custom_command: {
              name: "no-desc",
              prompt: "Test prompt",
              command_type: "global",
            },
          }
        end
        assert_redirected_to custom_commands_path

        command = AiHelperCustomCommand.last
        assert_nil command.description
      end
    end

    context "GET edit" do
      should "render edit form" do
        get :edit, params: { id: @global_command.id }
        assert_response :success
        assert_equal @global_command, assigns(:command)
      end

      should "not allow non-creator to edit" do
        other_user = User.find(3)
        @request.session[:user_id] = other_user.id

        get :edit, params: { id: @global_command.id }
        assert_response 403
      end
    end

    context "PATCH update" do
      should "update command" do
        patch :update, params: {
                   id: @global_command.id,
                   ai_helper_custom_command: {
                     prompt: "Updated prompt",
                   },
                 }
        assert_redirected_to custom_commands_path

        @global_command.reload
        assert_equal "Updated prompt", @global_command.prompt
      end

      should "not allow non-creator to update" do
        other_user = User.find(3)
        @request.session[:user_id] = other_user.id

        patch :update, params: {
                   id: @global_command.id,
                   ai_helper_custom_command: {
                     prompt: "Hacked prompt",
                   },
                 }
        assert_response 403

        @global_command.reload
        assert_not_equal "Hacked prompt", @global_command.prompt
      end

      should "validate on update" do
        patch :update, params: {
                   id: @global_command.id,
                   ai_helper_custom_command: {
                     name: "",
                   },
                 }
        assert_response :success
        assert_not_nil assigns(:command).errors[:name]
      end
    end

    context "DELETE destroy" do
      should "delete command" do
        assert_difference "AiHelperCustomCommand.count", -1 do
          delete :destroy, params: { id: @global_command.id }
        end
        assert_redirected_to custom_commands_path
      end

      should "not allow non-creator to delete" do
        other_user = User.find(3)
        @request.session[:user_id] = other_user.id

        assert_no_difference "AiHelperCustomCommand.count" do
          delete :destroy, params: { id: @global_command.id }
        end
        assert_response 403
      end

      should "redirect to project path when in project context" do
        delete :destroy, params: {
                    id: @project.id,
                    custom_command_id: @project_command.id,
                  }
        assert_redirected_to ai_helper_dashboard_path(@project, tab: "custom_commands")
      end
    end
  end
end
