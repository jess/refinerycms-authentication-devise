module Refinery
  module Authentication
    module Devise
      module Admin
        class UsersController < Refinery::AdminController

          crudify :'refinery/authentication/devise/user',
                  :order => 'username ASC',
                  :title_attribute => 'username'

          before_action :find_available_plugins, :find_available_roles,
                        :only => [:new, :create, :edit, :update]
          before_action :redirect_unless_user_editable!, :only => [:edit, :update]
          before_action :exclude_password_assignment_when_blank!, :only => :update

          def new
            @user = Refinery::Authentication::Devise::User.new
            @selected_plugin_names = []
          end

          def create
            @user = Refinery::Authentication::Devise::User.new user_params.except(:roles)
            @selected_plugin_names = params[:user][:plugins] || []
            @selected_role_names = params[:user][:roles] || []

            if @user.save
              create_successful
            else
              create_failed
            end
          end

          def edit
            @selected_plugin_names = find_user.plugins.map(&:name)
          end

          def update
            # Store what the user selected.
            @selected_role_names = params[:user].delete(:roles) || []
            @selected_role_names = @user.roles.select(:title).map(&:title) unless user_can_assign_roles?
            @selected_plugin_names = params[:user][:plugins]

            if user_is_locking_themselves_out?
              flash.now[:error] = t('lockout_prevented', :scope => 'refinery.authentication.devise.admin.users.update')
              render :edit and return
            end

            store_user_memento

            @user.roles = @selected_role_names.map { |r| Refinery::Authentication::Devise::Role[r.downcase] }
            if @user.update user_params.to_h
              update_successful
            else
              update_failed
            end
          end

          protected

          def create_successful
            @user.plugins = @selected_plugin_names

            # if the user is a superuser and can assign roles according to this site's
            # settings then the roles are set with the POST data.
            if user_can_assign_roles?
              @user.roles = @selected_role_names.map { |r| Refinery::Authentication::Devise::Role[r.downcase] }
            else
              @user.add_role :refinery
            end

            redirect_to refinery.authentication_devise_admin_users_path,
                        :notice => t('created', :what => @user.username, :scope => 'refinery.crudify')
          end

          def create_failed
            render 'new'
          end

          def update_successful
            redirect_to refinery.authentication_devise_admin_users_path,
                        :notice => t('updated', :what => @user.username, :scope => 'refinery.crudify')
          end

          def update_failed
            user_memento_rollback!

            render :edit
          end

          def find_available_plugins
            @available_plugins = Refinery::Plugins.registered.in_menu.map { |a|
              { :name => a.name, :title => a.title }
            }.sort_by { |a| a[:title] }
          end

          def find_available_roles
            @available_roles = Refinery::Authentication::Devise::Role.all
          end

          def redirect_unless_user_editable!
            unless current_refinery_user.can_edit? find_user
              redirect_to refinery.authentication_devise_admin_users_path
            end
          end

          private
          def exclude_password_assignment_when_blank!
            if params[:user][:password].blank? && params[:user][:password_confirmation].blank?
              params[:user].extract!(:password, :password_confirmation)
            end
          end

          def user_can_assign_roles?
            Refinery::Authentication::Devise.superuser_can_assign_roles &&
              current_refinery_user.has_role?(:superuser)
          end

          def user_is_locking_themselves_out?
            return false if current_refinery_user.id != @user.id || @selected_plugin_names.blank?

            @selected_plugin_names.exclude?('refinery_authentication_devise') || # removing user plugin access
              @selected_role_names.map(&:downcase).exclude?('refinery') # Or we're removing the refinery role
          end

          def store_user_memento
            # Store the current plugins and roles for this user.
            @previously_selected_plugin_names = @user.plugins.map(&:name)
            @previously_selected_roles = @user.roles
          end

          def user_memento_rollback!
            @user.plugins = @previously_selected_plugin_names
            @user.roles = @previously_selected_roles
            @user.save
          end

          def user_params
            params.require(:user).permit(
              :email, :password, :password_confirmation, :remember_me, :username,
              :login, :full_name, plugins: []
            )
          end
        end
      end
    end
  end
end
