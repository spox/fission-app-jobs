require 'base64'

class JobsController < ApplicationController

  helper_method :colorize

  COLOR_MAP = {
    '0' => 'reset',
    '1' => 'bold',
    '30' => 'black',
    '31' => 'red',
    '32' => 'green',
    '33' => 'yellow',
    '34' => 'lightblue',
    '35' => 'magenta',
    '36' => 'cyan',
    '37' => 'white'
  }

  def colorize(string)
    new_string = string.dup
    string.scan(/(\[(#{COLOR_MAP.keys.join('|')})(;1)?m)/).each do |result|
      if(result[1] == '0')
        new_string.sub!(result.first, '</span>')
      elsif(result[1] == '1')
        new_string.sub!(result.first, '<span style="font-weight: bold">')
      else
        style = Smash.new.tap do |s|
          s['color'] = COLOR_MAP[result[1]]
          if(result.last)
            s['font-weight'] = 'bold'
          end
        end
        style_string = style.map do |k,v|
          "#{k}: #{v}"
        end.join(';')
        new_string.sub!(result.first, "<span style=#{style_string.inspect}>")
      end
    end
    new_string
  end

  before_action :set_valid_jobs

  def all
    respond_to do |format|
      format.js do
        flash[:error] = 'Unsupported request!'
        javascript_redirect_to dashboard_path
      end
      format.html do
        @jobs = @valid_jobs.order(:created_at.desc).paginate(page, per_page)
        @namespace = @product.internal_name if @namespace.nil?
        enable_pagination_on(@jobs)
      end
    end
  end

  def details
    respond_to do |format|
      format.js do
        flash[:error] = 'Unsupported request!'
        javascript_redirect_to dashboard_path
      end
      format.html do
        @job = @valid_jobs.where(:message_id => params[:job_id]).first
        unless(@job)
          @job = Job.find_by_id(params[:job_id])
          if(@job && @job.account_id != @account.id)
            namespace = job.payload.get(:data, :router, :action)
            if(namespace && respond_to?("#{namespace}_job_path"))
              redirect_to send("#{namespace}_job_path", job.message_id, :account_id => @account.id)
            else
              redirect_to job_path(job.message_id)
            end
          else
            flash[:error] = "Failed to locate requested job (ID: #{params[:job_id]})"
            redirect_to dashboard_path
          end
        else
          @logs = Smash.new.tap do |logs|
            @job.payload.fetch(:data, {}).each do |k,v|
              if(v && v.is_a?(Hash) && v[:logs])
                v[:logs].each do |args|
                  if(args.is_a?(Array))
                    name, key = *args
                  else
                    i ||= 1
                    name = "Log #{i}"
                    i = i.next
                    key = args
                  end
                  begin
                    if(Rails.env.to_s == 'development')
                      logs[name] = Rails.application.config.fission_assets.get(key).read
                    else
                      logs[name] = Rails.application.config.fission_assets.url(key, 500)
                    end
                  rescue => e
                    logs[name] = 'FILE NOT FOUND!'
                  end
                end
              end
            end
          end
          @extra_table_data = load_custom_table_data(@job)
        end
      end
    end
  end

  def job_status
    respond_to do |format|
      format.js do
        last_id = params[:last_id].to_i
        @job = @valid_jobs.where(:message_id => params[:job_id]).first
        @events = @job.events.where{ id > last_id }.order(:stamp.asc).all
      end
      format.html do
        flash[:error] = 'Unsupported request'
        redirect_to dashboard_path
      end
    end
  end

  protected

  def load_custom_table_data(job)
    FissionApp::Jobs.custom_job_details.map do |custom_data|
      custom_data.call(job)
    end.compact.flatten(1)
  end

  def set_valid_jobs
    @valid_jobs = Job.dataset_with(
      :scalars => {
        :route => ['data', 'router', 'action'],
        :status => ['status']
      },
      :account_id => current_user.run_state.current_account.id
    ).where(
      :route => params[:namespace].to_s
    )
  end

  # Overload account loader and force redirect if different account
  # is required
  def load_current_account!
    super
    if(params[:job_id])
      @preload_job = Job.where(:message_id => params[:job_id]).last
      if(@preload_job && @preload_job.account_id && @preload_job.account_id != @account.id)
        redirect_to(
          :controller => controller_name,
          :action => action_name,
          :params => params.merge(:account_id => @preload_job.account_id)
        )
      end
    end
  end

end
