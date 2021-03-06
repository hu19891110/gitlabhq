class Groups::ApplicationController < ApplicationController
  layout 'group'

  skip_before_action :authenticate_user!
  before_action :group

  private

  def group
    unless @group
      id = params[:group_id] || params[:id]
      @group = Group.find_by_full_path(id)
      @group_merge_requests = MergeRequestsFinder.new(current_user, group_id: @group.id).execute

      unless @group && can?(current_user, :read_group, @group)
        @group = nil

        if current_user.nil?
          authenticate_user!
        else
          render_404
        end
      end
    end

    @group
  end

  def group_projects
    @projects ||= GroupProjectsFinder.new(group: group, current_user: current_user).execute
  end

  def authorize_admin_group!
    unless can?(current_user, :admin_group, group)
      return render_404
    end
  end

  def authorize_admin_group_member!
    unless can?(current_user, :admin_group_member, group)
      return render_403
    end
  end
end
