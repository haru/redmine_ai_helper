class AiHelperDashboardController < ApplicationController
  before_action :find_project, :authorize, :find_user

  def index
  end

  private

  def find_user
    @user = User.current
  end
end
